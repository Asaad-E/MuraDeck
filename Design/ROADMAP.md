# Roadmap / Known Gaps

From README's "Known Limitations" and FAQ — treat these as the open backlog, not just docs:

- **FSR/Sharp *and* Pixel scaling filters both break the gamescope session with reshade active** on current
  SteamOS. FSR case tracked upstream at
  [ValveGamescope#1903](https://github.com/ValveSoftware/gamescope/issues/1903). Pixel case root-caused via
  `journalctl` 2026-08: while gamescope's built-in reshade compiler (`gamescope_reshade`, distinct from desktop
  ReShade) (re)compiles a technique, it sometimes fails to resolve its own internal backbuffer bindings —
  `Couldn't find texture with name: V__ReShade__BackBufferTex` / `V__ReShade__DepthBufferTex` — then either
  crashes hard (`sddm-helper` reports "Process crashed", `systemd` tears down the whole Gamescope Session target
  — not just the game) or, in other repros, gets stuck retrying compilation and the system just becomes
  severely slow instead. Confirmed by the user as reproducible in normal use (not tied to a fresh
  install/reinstall) for months — any routine effect (re)application (game launch/close, brightness bracket
  change, profile switch, resume from suspend — anything that calls `_set_effect`/`_patch_fx`) while the system
  Scaling Filter is Pixel is enough to trigger it. Root cause is a gamescope-internal race/bug in its reshade
  technique compiler, not anything in MuraDeck's `.fx` sources or Python code. Only `LINEAR` is safe. This also
  means there is no in-plugin path to nearest-neighbor/pixel-perfect scaling for pixel-art games — see
  DECISIONS.md for why a ReShade-side "nearest" shader wouldn't be equivalent even if this bug weren't blocking
  the native filter. Workaround stays "use LINEAR + built-in CAS"; no in-plugin mitigation exists beyond warning
  the user before they hit it (not yet done — `pages/init.tsx` only tells them to set LINEAR, doesn't explain
  Pixel is equally unsafe). Partial mitigation shipped instead: "Pixel Art mode" (see DECISIONS.md) approximates
  a crisp pixel-art look via ReShade block-quantization while staying on LINEAR — not true nearest scaling, but
  avoids the crash entirely. Two follow-ups still open: (1) auto-detecting when the system Scaling Filter is set
  to Pixel/FSR and having MuraDeck back off automatically instead of relying on the user never touching that
  setting (needs research into whether the current filter is readable via an `xprop` atom, same class as
  `GAMESCOPE_FOCUSED_APP`); (2) filing the root-caused `gamescope_reshade` compiler bug upstream with the
  captured `journalctl` evidence.
- **Steam Remote Play breaks under reshade.** Workaround is external (Steam Link/Moonlight, or disabling
  Hardware Decoding + HEVC). Not something the plugin can currently detect or auto-adjust for.
- **Aspect ratio**: shaders assume 16:xx landscape; other ratios make mura correction look worse since the map
  is stretched/cropped rather than re-projected. `descriptor.ts` already reserves an `aspectfix` `EffectKey`
  that has no corresponding backend logic yet or UI toggle in `content.tsx` — that's the natural next slot for
  an aspect-ratio-aware correction feature. Detection approach used during development was `xwininfo` polling
  window resolution; timing it against actual window-open events was the hard part (per README).
- **HDR color-profile coverage is narrow by design** (see DECISIONS.md) — only HDR10PQ and HDRscRGB are
  tuned. Adding a new HDR profile means: a new `.fx` shader variant, a new `BRIGHTNESS_TABLE_*`, a new branch
  in `_set_profile`/`brightness_state`/`_patch_fx`'s `is_*` checks, and validation against real hardware —
  this is shader/color-science work, not just wiring.
- **CAS `descriptor.ts` entries (`cas`, `cas_slider`) are unused** — `content.tsx`'s AMD Fidelity FX section
  hardcodes its own labels instead of pulling from `Desc.cas`/`Desc.cas_slider`. Minor inconsistency to clean up
  if touching that section.
