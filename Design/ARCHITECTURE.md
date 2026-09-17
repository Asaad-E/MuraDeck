# Architecture Map

## Backend — `main.py` (single `Plugin` class, Decky loader entrypoint)

- **Settings**: `SettingsManager` (decky-provided `settings` module) persists everything under
  `DECKY_PLUGIN_SETTINGS_DIR`. Read once at import, written via `settings.setSetting(...)` + `settings.commit()`.
- **Effect files**: shaders live in `~/.local/share/gamescope/reshade/{Shaders,Textures}` (`RESHADE_DIR`).
  Plugin's own copies ship in `shaders/` (built from `defaults/shaders/*.fx`) and get installed into that dir
  by `_migration()` on first load / reinstall.
- **FX patching** (`_patch_fx`): mura shaders are plain-text `.fx` ReShade files. The plugin does NOT template
  them — it line-scans for known `uniform float ...` blocks (`CAS_Enabled`, `Sharpness`, `Pixelate_Enabled`,
  `Pixelate_BlockSize`, `MuraShadowGuard`, `MuraMapScale`, `MuraFadeNearWhite`, `Intensity`, `RGB_Lift`,
  `RGB_Gamma`) and rewrites each block's default value in place. See [DECISIONS.md](DECISIONS.md) for why.
  The scan keys off the exact declaration text and stops at the first line containing `>`, so a `ui_tooltip`
  must never contain one. `scratchpad/patch_harness.py`-style stubbing of `decky`/`settings` lets this be
  exercised off-device — worth doing after touching either side, since a silent mismatch ships a broken shader.
- **Effect switching** (`_set_effect`): gamescope watches the X root window property
  `GAMESCOPE_RESHADE_EFFECT`. The plugin sets it to a `_temp.fx` copy, sleeps 0.5s, then sets it to the real
  file — forces gamescope to reload even if the filename didn't change.
- **Profile detection** (`_log_watcher`): tails `console-linux.txt` / `gameprocess_log.txt`, regex-matches
  `colorspace: ... (HDR10_ST2084|SRGB_NONLINEAR|SRGB_LINEAR)` to infer SDR vs HDR10PQ vs HDRscRGB and calls
  `_set_profile`.
- **External monitor** (`_ext_monitor_watcher`): tails `systemdisplaymanager.txt` for gamescope's external-display
  event. When external, plugin switches to CAS-only mode (`_use_cas_only`) — no mura correction, since the fix is
  panel-specific to the internal display.
- **Brightness adaptation** (`brightness_state`, called from frontend's brightness listener): looks up the
  current profile's threshold table (`BRIGHTNESS_TABLE_*`) and re-patches/re-applies the effect when the
  bracket changes.
- **Shadow guard** (`set_mura_shadow_guard`/`get_mura_shadow_guard`, setting `mura_shadow_guard`): global, not
  per-app or per-display — how far up the tone range mura correction stays suppressed. See
  [DECISIONS.md](DECISIONS.md) for the shape of the curve and why it exists.
- **Per-app state**: CAS enabled/sharpness, Pixel Art mode/block size, and mura profile can be global or
  per-`appid` (`*_perapp_enabled` flag + `*_app_{appid}_{internal,external}` keyed settings, same shape for all
  three). `on_focus_change` / `on_game_state_update` (driven by frontend Steam event listeners) restore per-app
  profile on focus switch.
- **Pixel Art mode**: a block-quantization ReShade stage (`Pixelate_Enabled`/`Pixelate_BlockSize`, patched into
  the three profile shaders the same way CAS/Sharpness are) that gives pixel-art games a crisp blocky look
  without touching the system Scaling Filter — see [DECISIONS.md](DECISIONS.md) for why it can't be true
  nearest-neighbor scaling. Backend surface mirrors CAS exactly: `set_pixelate`/`get_pixelate`,
  `set_pixelate_block_size`/`get_pixelate_block_size`, `toggle_pixelate_perapp`, plus the matching
  `set_global_pixelate*`/`set_app_pixelate*` pairs.

## Frontend — `src/` (React/TSX via `@decky/ui`, `@decky/api`)

- **Entry**: `index.tsx` registers the sidebar route, the game-state listener, and calls `direct_effect()` on
  boot if the plugin was already enabled (so effect reapplies without waiting for the next trigger).
- **Panel**: `components/content.tsx` is the Quick Access Menu content — all the toggles/sliders shown there,
  backed by `refreshAll()` pulling current backend state on mount and on `monitor_changed` /
  `app_profile_applied` backend events (`@decky/api`'s `addEventListener`, paired with `decky.emit(...)` in
  `main.py`).
- **Full menu pages** (`pages/`): `menu.tsx` is the `SidebarNavigation` shell; `init.tsx` is the first-run
  setup checklist (developer mode / mura compensation / scaling filter); `status.tsx` shows shader install
  state, current display/colorspace, and plugin metadata (name/version/author sourced from `utils/rollup.ts`,
  injected at build time by `rollup.config.js`'s `@rollup/plugin-replace`).
- **Hooks** (`hooks/`): each wraps one Steam/gamescope event source into a `callable`/`call` bridge to the
  backend — `gameListener` (`SteamClient.GameSessions`), `brightnessListener`
  (`SteamClient.System.Display`), `resumeListener` (`SteamClient.System.RegisterForOnResumeFromSuspend`),
  `displayMode` (polls `get_display_mode`), `newUser` (first-run welcome redirect).
- **`components/defines/descriptor.ts`**: single source of truth for toggle labels/descriptions/icons
  (`Desc` map keyed by `EffectKey`), consumed by `content.tsx` and `EffectInfo`.
- **`components/styles/`**: presentational wrappers only (`EffectInfo`, `PlainButton`, `StatusButton`,
  `ParallelPanelSection`) — no logic beyond layout/tooltip plumbing.

## Shaders — `defaults/shaders/*.fx`

ReShade `.fx` sources: `MuraDeck_SDR.fx`, `MuraDeck_HDR10PQ.fx`, `MuraDeck_HDRscRGB.fx` (mura map + grain + LGG +
RCAS + Pixel Art, one per colorspace), `CAS.fx` (sharpening only, used standalone in CAS-only mode — no Pixel Art
stage there; the filename is historical, it runs RCAS like the rest). `ReShade.fxh` / `ReShadeUI.fxh` are the shared ReShade framework headers. These are edited as
HLSL/ReShade FX source, not TS/Python — editing them requires understanding ReShade's `uniform` annotation
syntax, since `_patch_fx` depends on exact `uniform float ...` declaration text matching.

The three profile shaders share a `SamplePixelated`/`SampleBlockAverage` helper pair: when `Pixelate_Enabled`
is on, the backbuffer is read through a box-supersampled (4 taps), block-quantized grid instead of a raw
per-pixel `tex2D` — this is the entry point for CAS (`ApplyCAS`), grain (via `GetGrainCoord` for a
block-coherent noise seed), and everything downstream. Mura correction's own `mura_uv` sampling is untouched by
this — it always reads at the true per-pixel coordinate, since it's a physical panel calibration, not part of
the game's rendered image.
