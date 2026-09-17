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

- **Mura is gated out of the shadows by `MuraShadowGuard`, and clamped to per-pixel headroom.** The map is
  applied as a fixed `±MuraMapScale/2` offset, so its size *relative to the pixel* explodes as the pixel darkens
  — at luma 0.02 it was a 347% perturbation. The existing `pow(luma, MuraFadeNearBlack)` fade was supposed to
  prevent that, but with the exponent tuned to ~0.02 it evaluates to ~0.94 at luma 0.05, i.e. it never engaged;
  the same is true of HDR10PQ's `pow(luma, 0.0)`. Because only red and green have maps (galileo ships no blue
  map, so blue is left untouched by design), the leftover perturbation is *chromatic*, which is why it read as
  coloured noise on dark greys and blues specifically. Two fixes, both deliberately shaped to leave the author's
  mid/highlight calibration untouched: a `smoothstep(MuraBlackCutoff, lerp(0.04, 0.40, guard), luma)` term that
  reaches 1.0 by luma ~0.25 (so correction above that is bit-identical to before), and a clamp of the offset to
  `min(color, 1-color)` so the negative half of the map can't clip at zero and leave only its positive half —
  that one-sided survival was itself a source of the raised, blotchy black this plugin exists to avoid.
  Exposed as one global slider rather than a per-game one: it's a property of the panel, not of the content.

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
  backbuffer into user-sized blocks, box-averaged over 9 texels to avoid moire — a deliberate stylized
  approximation, safe because it never touches the system scaler (stays on LINEAR, the only filter confirmed
  safe with reshade). Every tap snaps to a texel centre (`FetchTexel`): sampling at fractions of a block lets
  bilinear filtering blend in the neighbouring block, which made small block sizes come out *blurrier* than no
  pixelation at all. Block size is fractional (step 0.25) because upscale factors usually are — a game blown up
  1.6x needs 1.6, and forcing it to 2 beats against the game's real pixel grid. CAS's neighborhood sampling (`SampleOffset`) is made block-aware so CAS-with-pixelate
  sharpens *between* blocks instead of being a no-op inside one; grain's noise seed is snapped to the same block
  grid so dithering doesn't reintroduce per-real-pixel noise into an otherwise clean block. Mura correction
  itself intentionally still samples at the real per-pixel `mura_uv` — it's a physical panel calibration, not
  something that should follow the pixel-art grid.

- **Shader assets are installed, not bundled as static files loaded directly.** `_migration()` copies
  `defaults/shaders/*` into `~/.local/share/gamescope/reshade/Shaders` on first run/reinstall, and separately
  invokes `galileo-mura-extractor` / `galileo-mura-setup` (external SteamOS tools) to generate the per-device
  mura texture into `TEXTURE_DIR` — the mura map is unique per physical panel and can't ship as a static asset.
