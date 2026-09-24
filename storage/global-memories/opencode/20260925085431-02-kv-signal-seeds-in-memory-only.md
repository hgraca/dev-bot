---
date: 2026-09-25
keywords: ["opencode", "kv", "signal", "defaults", "plugin"]
trigger-on: ["opencode-kv-default-seeding", "opencode-kv-signal"]
---

## `kv.signal(name, default)` seeds into the in-memory store only — kv.json is written only on an explicit set, and that write snapshots the whole store

opencode's kv context exposes `signal(name, defaultValue)`, which runs `if (store[name] === undefined) setStore(name, defaultValue)` and returns the getter/setter pair; the seed lands in the **in-memory** store only, because the file (`~/.local/state/opencode/kv.json`) is written exclusively by `set`, which serialises a `structuredClone(unwrap(store))` — the **entire** store, not just the changed key. Three consequences when reasoning about defaults. (1) A key absent from the committed file can still be live in a running session, because the default was seeded in memory. (2) A key **present** in the file is not proof the user chose it — any unrelated `kv.set` flushes every seeded default to disk (opencode's own `tool_details_visibility: true` appears this way), so presence cannot distinguish an explicit choice from a leaked default. (3) The whole-store snapshot means a plugin writing kv at startup must wait for the store to be loaded (`kv.ready` gates the provider's children) or it persists a partial store and clobbers other keys. A TUI plugin calling `api.kv.set` is the supported way to seed a default, and it is safe against a view's own `signal(name, default)` because the plugin host awaits each plugin's `tui()` factory before the app gates its main UI on it — so the seed lands before any route mounts and seeds its default first.
