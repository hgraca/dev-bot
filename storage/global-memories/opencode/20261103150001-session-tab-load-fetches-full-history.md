---
date: 2026-11-03
keywords: ["opencode", "session", "load", "compaction"]
aliases: ["session tab slow", "session load slow", "compaction recent"]
trigger-on: ["opencode-session-load", "opencode-performance"]
---

## TUI session load fetches the full history, and compaction records duplicate it

Clicking a session tab is slow for large sessions even though the SQL is not: the TUI's message store calls `v2.session.messages({sessionID})` with no cursor/limit, so it loads every message in one payload (the endpoint supports `cursor.next`/`cursor.previous`, the TUI does not use them). Measured: a 1,555-message session is 17 MB and a 172-message session is 64 MB; the SQL query returns in <0.4 s, so the cost is payload transfer, JSON parsing, and terminal rendering.

Two multipliers: compaction records (`type='compaction'`) store a `recent` field (~2.5 MB of raw recent history) alongside a small `summary` — ten compactions in one session added ~25 MB — controlled by `compaction.keep.tokens` (`preserve_recent_tokens`, default `min(15000, max(2000, 25% of context))`), and `recent` is not rendered, only fed to the next compaction. Large pasted user messages (multi-MB blobs) inflate `session_message` too. Pruning the v2 session store is the effective reclaim; trimming `recent` is safe only for sessions that will not be compacted again.
