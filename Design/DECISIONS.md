# Decisions

- **FX files are patched as text, not templated.** ReShade `.fx` files are shipped as static defaults and the
  plugin rewrites specific `uniform float ... < ... > = value;` blocks in place at runtime
  (`Plugin._patch_fx`). Alternative would be a templating layer or per-value external config file, but ReShade
  reads `.fx` source directly and re-parses on effect switch, so patching the file that's already on disk is
  the simplest thing gamescope/ReShade understands with zero extra glue. Trade-off: patching is brittle to
  exact `uniform float <Name>` text matching — renaming a uniform in the shader source requires updating the
  matching string in `_patch_fx`.

- **Effect switch does a two-step temp-file swap** (`_set_effect`: set to `X_temp.fx`, sleep 0.5s, set back to
  `X.fx`). Gamescope's `GAMESCOPE_RESHADE_EFFECT` property only reloads on a *value change*; reapplying the
  same filename after a mid-session patch wouldn't trigger a reload otherwise, since gamescope is not aware the
  underlying file content changed.

- **CAS-only mode when an external monitor is connected.** The mura correction map is calibrated to this
  specific internal panel; applying it to an external display would be wrong. Rather than fully disabling the
  plugin, CAS (sharpening) — which is display-agnostic — stays active. Toggled via `_use_cas_only`, watched by
  `_ext_monitor_watcher` tailing gamescope's display-manager log.

- **Per-app profile caching** (`_app_profile_cache`, `on_focus_change`) exists because SDR/HDR detection is
  driven by parsing gamescope's live log stream, which reflects whatever app currently has focus — without a
  cache, switching focus back to a previously-detected HDR game would show stale/default SDR until a fresh log
  line arrives. The cache is intentionally cleared when a game closes (`on_game_state_update`), not persisted
  across plugin restarts.

- **HDR detection is deliberately conservative** (see README FAQ): only HDR10PQ and HDRscRGB colorspaces get a
  dedicated shader; anything else falls back to SDR rather than guessing. Each HDR colorspace needs its own
  fine-tuned mura curve — applying the wrong one is worse than not correcting at all.

- **Mura correction scales with the pixel's own level, rather than being gated out of the
  shadows.** The map is applied as a fixed `±MuraMapScale/2` offset, so its size *relative to
  the pixel* explodes as the pixel darkens — at luma 0.02 it was a 347% perturbation, and
  since only red and green have maps (galileo ships no blue one, so blue is untouched by
  design) the leftover was *chromatic*, which is why it read as coloured noise on dark greys
  and blues specifically. The `pow(luma, MuraFadeNearBlack)` fade meant to prevent this
  evaluated to ~0.94 at luma 0.05, i.e. it never engaged. First fix was a smoothstep gate;
  this replaces it with `lerp(1.0, saturate(luma / 0.5), MuraResponse)`, which is how demura
  actually works — industry measures the panel at several grey levels because a pixel's
  deviation tracks its drive level, and scaling by level is the one-map approximation of
  that. Measured against a mura-free reference it beats the gate in every tone band (2.14 vs
  2.62 in the mids) and needs no hand-picked threshold. The offset is still clamped to
  `min(color, 1-color)` so the map's negative half cannot clip at zero and leave only its
  positive half, which is itself a source of raised, blotchy black. `MuraResponse` is exposed
  because a real panel mixes gain and offset error and only the user's eyes can settle the
  blend; 0 restores the flat-offset behaviour.

- **Sharpening is RCAS (FSR 1.0's second pass), not CAS.** Position in the pipeline decides
  this: gamescope has already scaled the frame by the time reshade sees it, and RCAS is the
  pass AMD wrote for sharpening an already-upscaled image, while CAS assumes a natively
  rendered one. RCAS also carries a noise-detection term — measured on synthetic cases, its
  edge-response to speckle-response ratio is 3.11 against CAS's 1.40, i.e. it is ~2.2x better
  at sharpening detail rather than grain, which is what made the old sharpening read as
  added noise. It is also cheaper: a 5-tap cross instead of CAS's 9 taps. Ported verbatim
  from `ffx_fsr1.h` and checked against the reference to 2.2e-16 over 20k random
  neighbourhoods. Trade-off worth knowing: at the same slider position RCAS is roughly half
  as strong, because `FSR_RCAS_LIMIT` is where AMD caps "natural" sharpening and the
  sharpness factor only scales below it — CAS had no such ceiling.

- **The sharpness slider maps onto RCAS stops, so its low end is actually low.** AMD's
  parameter is in stops of reduction (`sharpness = exp2(-stops)`); the 0..1 slider maps onto
  [2, 0] stops. Under the old CAS, slider 0 was documented as "no sharpening" but still
  boosted a fine detail by ~16% — there was no gentle setting at all, only off or strong.
  Slider 0 now measures ~2%. The uniform is still named `Sharpness` with the same 0..1
  range, so `_patch_fx` is untouched.

- **scRGB is normalised before sharpening and restored after.** RCAS's limiter is built
  around a 1.0 signal ceiling (AMD's `peakC = (1.0, -4.0)`), but scRGB is linear and
  unbounded. Under the old CAS this meant `2.0 - mx` went negative and `saturate` drove the
  sharpening amount to exactly zero, so sharpening silently switched itself off on anything
  brighter than SDR white — sharp in the dark parts of an HDR frame, absent in the bright
  ones. `RcasEncode`/`RcasDecode` (`x/(1+x)` and its inverse) map into [0,1) and back, which
  is what AMD's `FsrRcasInputF` hook is for; measured sharpening is now consistent (~5%)
  from 0.5 to 8.0 instead of dying at 1.0.

- **Dithering uses Interleaved Gradient Noise, not the Box-Muller gaussian it was written with.** The gaussian
  is unbounded, so its tails landed as bright specks on flat dark areas, and white noise puts its energy exactly
  where the eye is most sensitive; it was also `Timer`-driven, and the resulting shimmer is what made it
  register as noise at all. IGN is bounded to [0,1) and high-frequency, so it breaks banding just as well at the
  same `Intensity` and is far harder to see. `Variance`/`Mean` still scale it, so `_patch_fx` is unchanged.

- **Pixel Art mode is a ReShade block-quantization effect on top of LINEAR, not gamescope's native Pixel
  filter.** True nearest-neighbor is off the table two ways: (1) MuraDeck's shaders all read
  `ReShade::BackBuffer`/`ReShade::ScreenSize` — the *already gamescope-scaled* frame — so by the time any
  ReShade effect runs, the low-res source pixels are gone; nothing in reshade can reconstruct true crisp nearest
  scaling from that. (2) Setting gamescope's native Pixel filter ourselves (mirroring how `_set_effect` writes
  `GAMESCOPE_RESHADE_EFFECT` via `xprop`) wouldn't help either — root-caused via `journalctl` to a bug in
  gamescope's own reshade technique compiler (`gamescope_reshade`), which can fail to resolve its internal
  `V__ReShade__BackBufferTex`/`DepthBufferTex` bindings and then either crash the session or spin retrying (see
  ROADMAP.md for the log evidence); this triggers from any normal effect (re)application while Pixel is active,
  so setting the filter through a different code path hits the identical upstream bug. Given that, "Pixel Art
  mode" (`Pixelate_Enabled`/`Pixelate_BlockSize` in the three profile `.fx` files, backend methods
  `set_pixelate`/`set_pixelate_block_size` etc. in `main.py`) instead re-quantizes the already-linear-scaled
  backbuffer into user-sized blocks — a deliberate stylized approximation, safe because it never touches the
  system scaler (stays on LINEAR, the only filter confirmed safe with reshade). Each block takes one texel from
  its centre, snapped to a texel centre (`FetchTexel`), because sampling anywhere else lets bilinear filtering
  blend in the neighbouring block — which made small block sizes come out *blurrier* than no pixelation at all.
  An earlier version box-averaged nine taps instead; those taps snapped to texel centres after being placed at
  1/6, 1/2 and 5/6 of the block, which put the sampled centroid off the block's true centre by up to half a
  texel, by a different amount at each block size, so the picture shifted as the slider moved — and measured
  *softer* than a single centre tap (0.0062 against 0.0095 edge energy at block 2.25), i.e. the averaging was
  costing the mode the crispness it exists for. Block size is fractional (step 0.25) because upscale factors
  usually are — a game blown up 1.6x needs 1.6, and forcing it to 2 beats against the game's real pixel grid.
  `SampleOffset` is block-aware so RCAS sharpens *between* blocks rather than inside one, and routes centre and
  neighbours through the same estimator: when the centre was an average and the neighbours single taps, the two
  disagreed by up to half the range and RCAS read that as image content. Grain's noise seed is snapped to the
  same grid so dithering doesn't reintroduce per-real-pixel noise into an otherwise clean block. Mura correction
  itself intentionally still samples at the real per-pixel `mura_uv` — it's a physical panel calibration, not
  something that should follow the pixel-art grid.

- **Shader assets are installed, not bundled as static files loaded directly.** `_migration()` copies
  `defaults/shaders/*` into `~/.local/share/gamescope/reshade/Shaders` on first run/reinstall, and separately
  invokes `galileo-mura-extractor` / `galileo-mura-setup` (external SteamOS tools) to generate the per-device
  mura texture into `TEXTURE_DIR` — the mura map is unique per physical panel and can't ship as a static asset.
