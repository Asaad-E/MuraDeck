# Code Style

## Python (`main.py`)

- Every plugin-callable method is `async def`, even ones that do no I/O — Decky's RPC bridge requires it.
- Log through `decky.logger.info/warning/error`, always prefixed `[MuraDeck]` (and a bracketed sub-tag like
  `[Brightness]`, `[Monitor Watcher]`, `[Resume]` when it's a specific subsystem) — never bare `print`
  (one exception exists in `get_steam_icon`, don't copy it).
- Settings pattern: `settings.setSetting(key, value)` then `settings.commit()` in the same call, and mirror the
  value into an instance attribute (`self._foo`) so subsequent logic doesn't re-read from disk.
- Long-running watchers (`_log_watcher`, `_ext_monitor_watcher`) are `asyncio.create_task`'d and guarded with
  `is None or .done()` checks before restarting, cancelled with `.cancel()` + `await` swallowing
  `CancelledError`. Follow this pattern for any new background watcher rather than inventing another shape.
- Global vs per-app settings keys follow `{feature}_global_{internal,external}` /
  `{feature}_app_{appid}_{internal,external}` with a separate `{feature}_perapp_enabled_{appid}` flag deciding
  which one wins (see `get_cas`/`get_sharpness` for the read-side pattern). New per-app-capable settings should
  reuse this exact naming shape.

## TypeScript / React (`src/`)

- Function components only, no classes. State via `useState`, side effects via `useEffect` +
  `useCallback` for anything passed to an effect's dependency array.
- Backend calls go through `@decky/api`'s `call<[ArgTypes], ReturnType>("python_method_name", ...args)` for
  one-off calls, or `callable<[ArgTypes], ReturnType>("python_method_name")` when the same call is reused across
  a module (see `hooks/*.tsx`). Argument tuple and return type must match the Python method's signature.
- Backend→frontend push uses `addEventListener`/`removeEventListener("event_name", handler)` paired with
  `decky.emit("event_name", payload)` on the Python side — always unregister in the `useEffect` cleanup.
- UI copy (toggle labels/descriptions/icons) lives centrally in `components/defines/descriptor.ts`'s `Desc` map,
  not inlined in JSX — add new `EffectKey` entries there.
- Toggles that trigger a backend side effect with a visible delay use the `delayToggle` helper in
  `content.tsx` (optimistic state update + loading flag + artificial 500ms settle) rather than a bare
  `onChange` + `call`.
