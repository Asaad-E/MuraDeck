# Working on MuraDeck

**Before doing anything**, read **[`Design/README.md`](Design/README.md)** — it links to 5 short docs (project brief, architecture map, code style, decisions, roadmap) covering current state. Together under 2,000 words; read all five before starting real work, not just the one that seems most relevant.

**Before ending your turn**, if you made a real change (new file, new public API, a fixed bug worth remembering, a decision someone might otherwise re-litigate): update the relevant Design/ doc in the same turn — ARCHITECTURE.md for what now exists, DECISIONS.md for why, ROADMAP.md if it closes or opens a gap. Prefer editing an existing line over appending a new one — these docs should stay roughly constant-size as the project grows, not accumulate. Skip this for trivial changes (typo fixes, pure refactors with no behavior change) — don't pad the docs for its own sake.

## Project-specific notes

- This is a [Decky Loader](https://decky.xyz) plugin — Python backend (`main.py`) + React/TS frontend (`src/`), built with `pnpm build` (rollup). It only runs meaningfully on a real Steam Deck OLED (gamescope, `xprop`, `SteamClient` are all runtime-only — nothing here is unit-testable off-device without mocking).
- Shader files under `defaults/shaders/*.fx` are ReShade FX source (HLSL-like), not TS/Python — see [Design/ARCHITECTURE.md](Design/ARCHITECTURE.md#shaders--defaultsshadersfx) before editing them, since `main.py`'s `_patch_fx` depends on exact uniform-declaration text matching.
- `settings` (imported in `main.py`) is provided by the Decky loader runtime, not part of this repo — don't go looking for it under `src/`.
