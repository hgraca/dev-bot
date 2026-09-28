---
date: 2026-09-29
keywords: ["opencode", "prune", "session-registry", "vacuum", "retention"]
---

## Prune the opencode DB only when the last devbot session exits

`devbot prune --db` deletes opencode rows older than a retention (default 30 days, overridable with `DEVBOT_OPENCODE_DB_RETENTION_DAYS`) and `VACUUM`s the file to reclaim disk, since the `event` replay journal is the bulk of a large database and opencode ships no retention job. It fires detached from `_devbot_session_release` at the install-level last-one-out point (the flock session registry), not from a harness hook: that point already runs exactly once when the live session count reaches zero, and it must not depend on the docker daemon — so the prune sits beside `_devbot_session_teardown`, not inside it. `project` rows are never age-pruned: `session.project_id` cascades _from_ `project`, so deleting an aged project would take its live sessions with it. The helper lives next to its sibling opencode-DB consumer at `src/harnesses/opencode/prune_opencode_db.py` and shares the XDG-aware `opencode_db.resolve_db_path` with `stats.py`. The detached child closes fd 200 (registry lock) and fd 210 (session lock) so it cannot pin the registry flock past exit. Safety is fail-open: a missing, corrupt, or busy database, or a running opencode, is reported and changes nothing.
