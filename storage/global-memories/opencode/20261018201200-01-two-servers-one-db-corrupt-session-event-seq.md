---
date: 2026-10-18
keywords: ["opencode", "session-seq", "sqlite", "unique-constraint", "prompt_async"]
aliases: ["prompt sending fails", "second opencode server", "event.aggregate_id event.seq", "v2 migration session stuck"]
trigger-on: ["opencode-session-store", "opencode-multi-server"]
---

## Two opencode servers on one database fork a session's event seq and brick prompt sending

When a second opencode server (for example a v2 `@opencode/cli` instance running beside the v1 CLI) opens the same `~/.local/share/opencode/opencode.db`, prompt sending can fail permanently for whichever session it had loaded: the log shows `prompt_async failed` with `EffectDrizzleQueryError: ... insert into "event" ... (SQLiteError: UNIQUE constraint failed: event.aggregate_id, event.seq)`, a prompt is never persisted, and the session appears frozen — no new messages appear even though the UI accepts the text. The mechanism is that each process allocates the next `seq` for a session from its own in-memory copy of the aggregate; a server that loaded the session earlier keeps retrying a `seq` the other process already wrote (the failing seq sits far below `max(seq)` for that aggregate). Confirm by comparing the failing `seq` in the log against `select max(seq) from event where aggregate_id='<ses_id>'`: if the max is far ahead, the counters are forked, and `select seq from event where aggregate_id='<ses_id>' and seq=<failing>` shows the row already taken. Fix it by ensuring exactly one server owns the database — kill the stale/second instance so it reloads `seq` from the table; restarting the current server also works. Do not delete `event` rows: the data is consistent, only the writer is stale. The same duplicate-owner condition also surfaces as `failed to add snapshot files ... index.lock: File exists` warnings while both processes snapshot the same checkout.
