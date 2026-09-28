---
date: 2026-09-29
keywords: ["opencode", "event-sequence", "cascade", "sqlite", "prune"]
trigger-on: ["opencode-database", "opencode-event-journal"]
---

## Deleting an opencode session does not remove its event journal

`event_sequence` has **no foreign key to `session`** (`event` cascades only from `event_sequence.aggregate_id`, and nothing cascades into `event_sequence` from `session`), so `DELETE FROM session` leaves the session's replay journal behind — this is how `event` grows to ~13 GB while `session` stays small. The journal's aggregate id _is_ the session id (verified live: 1131/1131 `event_sequence.aggregate_id` matched a `session.id`; `owner_id` is unused, all NULL), so to prune it by age join through the session: `DELETE FROM event_sequence WHERE aggregate_id IN (SELECT id FROM session WHERE time_updated < ?)` — the `event` rows cascade from there. Rows whose session is already gone (left by opencode's own `session delete`) have no timestamp to age on and can only be removed outright with `aggregate_id NOT IN (SELECT id FROM session)`; that is safe offline because opencode holds no in-flight aggregate when it is not running.
