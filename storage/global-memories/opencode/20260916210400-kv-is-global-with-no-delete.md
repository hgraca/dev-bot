---
date: 2026-09-16
keywords: ["opencode", "kv", "plugin-state", "defaults"]
trigger-on: ["opencode-plugin-kv", "opencode-tui-kv"]
---

## `api.kv` is one store shared by every opencode process, it has no delete, and a stored value always beats a changed default

`api.kv.get/set` reads and writes a single file (`~/.local/state/opencode/kv.json`) shared by **every** opencode process on the machine, while most plugin state is per-process. Two consequences. (1) An un-namespaced key that means something per-process (e.g. a server this plugin started, on a random port) lets one instance overwrite another's value, after which both thrash — namespace such keys, and prefer an **in-memory** variable when the value is per-process, because `TuiKV` exposes only `get`/`set`/`ready` and **has no delete API**: a per-PID key leaks one stale entry on every single start, forever. (2) Genuinely global preferences (a sidebar's collapsed state) belong in kv unscoped, and other plugins namespace theirs (`opencode-tabs:tabs:v1:<hash>:`). Related trap when flipping a default: **a stored value always wins over the default**, so changing a default silently does nothing for existing users — version or rename the key when the default's meaning changes.
