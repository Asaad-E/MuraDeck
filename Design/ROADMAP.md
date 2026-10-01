# Roadmap / Known Gaps

From README's "Known Limitations" and FAQ — treat these as the open backlog, not just docs:

- **FSR/Sharp *and* Pixel scaling filters both break the gamescope session with reshade active** on current
  SteamOS. FSR case tracked upstream at
  [ValveGamescope#1903](https://github.com/ValveSoftware/gamescope/issues/1903). Pixel case reproduced by the user for months in normal use (not tied to a fresh install): any routine
  effect (re)application — game launch/close, brightness bracket change, profile switch, resume — while the
  system Scaling Filter is Pixel either restarts the whole Gamescope Session (`sddm-helper` reports "Process
  crashed", not just the game) or leaves the system severely slow. **The mechanism is not established.** An
  earlier version of this note blamed `Couldn't find texture with name: V__ReShade__BackBufferTex` /
  `DepthBufferTex` in the journal, but a later log (2026-10) shows those same two lines on every ordinary
  MuraDeck apply across an hour of healthy sessions with no crash, so they are routine noise from
  `gamescope_reshade`, not the cause. What is known: it needs Pixel/FSR scaling plus reshade active, and it
  is not something MuraDeck's `.fx` sources or Python code does by themselves. Only `LINEAR` is safe. This also
  means there is no in-plugin path to nearest-neighbor/pixel-perfect scaling for pixel-art games — see
  DECISIONS.md for why a ReShade-side "nearest" shader wouldn't be equivalent even if this bug weren't blocking
  the native filter. Workaround stays "use LINEAR + built-in CAS"; no in-plugin mitigation exists beyond warning
  the user before they hit it (not yet done — `pages/init.tsx` only tells them to set LINEAR, doesn't explain
  Pixel is equally unsafe). Partial mitigation shipped instead: "Pixel Art mode" (see DECISIONS.md) approximates
  a crisp pixel-art look via ReShade block-quantization while staying on LINEAR — not true nearest scaling, but
  avoids the crash entirely. Two follow-ups still open: (1) auto-detecting when the system Scaling Filter is set
  to Pixel/FSR and having MuraDeck back off automatically instead of relying on the user never touching that
  setting (needs research into whether the current filter is readable via an `xprop` atom, same class as
  `GAMESCOPE_FOCUSED_APP`); (2) filing it upstream, but only once the actual failing line is found — the journal lines
  captured so far do not distinguish a crash from normal operation.
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
- **Multi-pass shaders are not available.** A two-pass probe with a render target was run on the Deck (2026-10):
  gamescope_reshade accepted the technique (`Using technique: MuraDeckPassTest`) and the whole session died before
  the usual `Compiling pass:` line — black screen, then a fresh Gamescope Session ~9s later. Which of the probe's
  three new things triggers it (a texture with no `source`, a `RenderTarget`, or two passes) was not isolated;
  each variant costs a session restart. Everything here is single-pass because of it.
- **Debanding** is a candidate: a different problem from AA (colour quantisation steps in smooth gradients, the
  README's near-black banding complaint). The IGN dither already breaks steps at 1 LSB; debanding would take the
  larger ones. Single-pass and cheap.
- **CAS `descriptor.ts` entries (`cas`, `cas_slider`) are unused** — `content.tsx`'s AMD Fidelity FX section
  hardcodes its own labels instead of pulling from `Desc.cas`/`Desc.cas_slider`. Minor inconsistency to clean up
  if touching that section.
