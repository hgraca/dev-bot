---
date: 2026-11-22
keywords: ["opencode", "session_v2", "part", "migration", "tool-calls"]
aliases: ["two stores", "flattened tool calls", "session_message prose"]
---

## A migrated 1.x opencode session keeps its tool calls in `part`, not the v2 message stream
A 1.x session that appears in `session_v2` also still has its structured `part` rows, and those are the only faithful record of its tool calls: the migrated `session_message` stream has flattened them into prose inside text parts (`[tool bash: completed] …`). Reading `session_message` for such a session yields zero tool calls and silently loses every command, which is hard to notice because the session count still looks right. Decide per session: if `part` rows with `type = 'tool'` exist, read them and ignore the stream; only v2-native sessions (no `part` rows) should be read from `session_message`. Sessions that exist in both tables must be deduplicated by id with the `session_v2` row winning, and the newest sessions live only in `session_v2` — so a store merged by "newest N" needs the union, not one table.
