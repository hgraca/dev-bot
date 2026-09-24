---
date: 2026-09-25
keywords: ["opencode", "sqlite", "event-table", "database"]
trigger-on: ["opencode-database", "opencode-storage"]
---

## opencode's SQLite `event` table is the bulk of the database, and database size does not slow startup

opencode keeps everything in `${XDG_DATA_HOME:-~/.local/share}/opencode/opencode.db`. In a real 16.6 GB instance, `part` measured 2.16 GB and `message` 0.75 GB by full scan, leaving roughly 13 GB in **`event`** — a per-session replay journal (`aggregate_id` is the session id, `seq` a per-session counter, `type` values like `message.part.updated.1`) holding ~1.39 M rows across only ~1,024 sessions. Two conclusions follow. (1) **Size is not a startup cost**: opening the database and running a trivial query measured 5 ms, because SQLite does not scan at open — the `PRAGMA wal_checkpoint(PASSIVE)` opencode runs on open is bounded by the WAL, not the file. (2) The journal is derived state: opencode itself runs `DELETE FROM event; DELETE FROM event_sequence;` in a workspace-cleanup migration, so it can be trimmed (offline, then `VACUUM`, or `VACUUM INTO` to a new file) to reclaim the space without touching sessions or messages — but opencode ships no retention job, so nothing does this automatically.
