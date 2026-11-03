---
date: 2026-11-03
keywords: ["devbot", "prune", "opencode", "session_v2"]
aliases: ["opencode db prune", "prune --db", "session_message cascade"]
---

# The opencode DB prune must delete `session_v2`, not just `session`

The prune helper (`src/harnesses/opencode/prune_opencode_db.py`) originally deleted only v1 `session` rows, assuming `session_message` cascaded from `session`. It does not: opencode keeps two stores — v1 `session` (cascading to `message`/`part`/`todo`/`session_share`) and v2 `session_v2` (cascading to `session_message`/`instruction_entry`/`instruction_state`/`session_pending`/`session_inbox`). A 30-day prune therefore left 698 v2-only sessions and ~844 MB of `session_message` in an 11 GB DB; the DB shrank 12 GB → 11 GB and old sessions stayed loadable.

Fix (PR #48): delete `session_v2` rows older than the cutoff, guarded by a `sqlite_master` table-exists check for older schemas, and count v2 sessions in the report. `event_sequence` has no FK to either store, so its early delete must exclude ids still live in a recent v2 session (`_live_session_ids` union). Tests: `bin/tests/prune_db_tests.bats` covers the v2 cascade, a shared v1/v2 id, and a v1-only schema.
