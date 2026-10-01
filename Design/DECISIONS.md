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
  this replaces it with `lerp(1.0, color / 0.5, MuraResponse)` per channel, which is how demura
  actually works — industry measures the panel at several grey levels because a pixel's
  deviation tracks its drive level, and scaling by level is the one-map approximation of
  that. Measured against a mura-free reference it beats the gate in every tone band (2.14 vs
  2.62 in the mids) and needs no hand-picked threshold. The offset is still clamped to
  `min(color, 1-color)` so the map's negative half cannot clip at zero and leave only its
  positive half, which is itself a source of raised, blotchy black. `MuraResponse` is exposed
  because a real panel mixes gain and offset error and only the user's eyes can settle the
  blend; 0 restores the flat-offset behaviour. The weight is per channel and uncapped: a
  gain error has to be cancelled in proportion to *the value being corrected*, so scaling
  red by luma is wrong on saturated colour (red 0.6 against luma 0.22), and capping the
  weight at 1.0 under-corrects everything above mid grey. Driven by the real maps off this
  panel, fixing both takes the visible luma residual from 0.846 to 0.340 — 16% of the
  uncorrected noise, against 39% before.

- **Blue is structurally uncorrectable, and that is the floor.** Both galileo maps are
  single-channel greyscale, so no blue data exists; the shader's `tex2D(...).rgb` reads are
  just the same grey replicated. Nor can blue be inferred: measured on this panel's own
  maps, red and green correlate at 0.0004, and there is no shared low-frequency component
  to extrapolate from either (92% of each map's variance is per-pixel grain; by a 2px blur
  under 0.6% of it survives). The mura is per-subpixel and independent, so red and green
  carry no information about blue. What saves it is weighting: blue is 7% of luma, so with
  red and green corrected properly the eye sees ~84% of the mura gone, and the remainder is
  blue-ish chroma noise rather than luminance grain.

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

- **Sharpening can be luminance-only.** RCAS runs per channel, so it also sharpens the colour noise in red,
  green and blue, and on this panel red and green are corrected separately so their residual is uncorrelated.
  Adding only the brightness change to every channel keeps the edge and drops the rest. Measured: chroma noise
  on a flat field goes 9.5 -> 23.6 under per-channel RCAS (2.5x) and stays 9.5 luma-only; on a red-to-teal edge
  per-channel adds a 37/1000 hue shift, luma-only none; luminance edge contrast is identical. Off by default.

- **Mura strength is a multiplier on a separate uniform, not a slider on `MuraMapScale`.** The brightness table
  rewrites `MuraMapScale` on every brightness change, so writing the slider there would be overwritten the next
  time the brightness moved. 0.5x-1.5x on top of the adapted value keeps adaptation intact.

- **Anti-aliasing is FXAA, optional, per game, off by default, and every parameter was measured.** MSAA, SSAA,
  TAA and DLAA need the rasteriser, depth or motion vectors, none of which exist after composition, so only an
  FXAA-class filter is possible. Judged on scenes drawn at 8x with no AA (the box-reduced image is the ground
  truth, one sample per pixel is the aliased input): it removes about a third of the error on sloped and curved
  edges (polygon -47%, circles -30%, angled lines -17%) but does little for text (-12%), so what it buys depends on
  how much of the picture is slanted geometry. It softens: on content that is *already* anti-aliased it still
  changes ~4% of pixels, which is why it is per game and not a global default. Choices, with what decided them:
  subpixel **0.25**, not the stock 0.75 — 0.75 softens 1px lines and text (+33% error on thin features) and
  0.25 beat it on every axis, though a still image cannot reward the shimmer reduction the subpixel term exists
  for, so that is a judgement; threshold 0.166 and minimum 0.0312 (the minimum matters on near-black, where
  0.0312 removed 27.5% of the aliasing error against 24.4% for 0.0625; the relative threshold barely mattered);
  search distances **1,2,4,8,16,32** because long shallow edges need reach, not density — the same budget spent
  linearly left the long flat edge at 33.0 against 22.2. The formulation uses exact texel fetches only: FXAA moves
  perpendicular to the edge, so its final sample is a lerp of two texels and each probe the mean of two, and it
  does not depend on the sampler's filter mode (the HLSL was transcribed to scalar Python and matched the measured
  vectorised version on 9000 of 9000 pixels). Average cost is ~5.8 fetches per pixel, p99 ~25, worst 33 — only
  the edge pixels pay, most exit on the contrast test. Order: before RCAS (AMD requires FSR's input to be
  anti-aliased) and before mura, whose per-subpixel correction a blur would smear; it switches itself off with
  Pixel Art mode, since smoothing quantised blocks undoes it. Only RCAS's *centre* tap is anti-aliased; scored
  against RCAS run on the clean image the hybrid gave 21.05 against 21.54 for anti-aliasing all five taps (and
  20.97 for sharpening first), at a fraction of the fetches — the claim that mixed estimators hurt, true for the
  Pixel Art average, does not hold here because FXAA moves a pixel at most halfway to one neighbour. A
  second pass with a render target would have been the other route, but the probe showed gamescope_reshade
  takes the session down on it (see ROADMAP.md).

- **Debanding is optional, SDR-only, and only clearly helps shallow dark gradients.** Dithering the output cannot
  remove source banding: a plateau sits on an integer level and rounds straight back to it (banding 0.126 with
  dither, 0.126 without). What works is averaging across the step to recover the fractional ramp and then
  dithering to write it back into 8 bits; deband in float then re-quantised *without* dither returns exactly to
  the source banding (0.890 -> 0.890), so the dither is not optional, and it goes at the very end of the shader
  so LGG and mura cannot rescale it. Design: four rings of two opposite taps at radii 2/4/8/16, angle hashed per
  pixel and turned by the golden angle each ring, each tap counted only if within 2.5/255 of the centre in every
  channel. Radii 2/4/8/16 over 4/8/16/32 because larger reach did better on a plain ramp (0.385 vs 0.418) and
  worse on curved gradients. Honest result, in relative linear luminance: dark ramp 0.890 -> ~0.41% (-54%,
  stable across two runs); a mid-tone ramp and a curved vignette moved within the noise of a metric that
  measures tenths of a percent (an earlier run's -31% on the mid ramp did not reproduce). It adds about a level
  of fine noise (1.56 -> ~2.4%). Order: shipped as RCAS then deband with the RCAS output as the centre and raw
  taps, which measured the same as running with RCAS off and never worse; deband-then-RCAS was better on the dark
  ramp (0.266) and worse on the vignette (0.558 vs 0.483), so it was not preferred. SDR only: HDR10 PQ and scRGB
  have the range it needs and a 1/255 dither would be gratuitous noise there. Off by default; 8 extra fetches per
  pixel, with no early-out.

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
  `GAMESCOPE_RESHADE_EFFECT` via `xprop`) wouldn't help either — the crash with Pixel active reproduces through Steam's own
  settings UI, so forcing the same filter through a different code path would hit it too. Its mechanism is
  not established: the `V__ReShade__BackBufferTex`/`DepthBufferTex` lines first suspected turned out to appear
  on every ordinary effect apply in healthy sessions (see ROADMAP.md), so they are noise, not the cause. Given that, "Pixel Art
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
