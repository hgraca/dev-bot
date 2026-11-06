---
date: 2026-11-06
keywords: ["opencode", "prune", "vacuum", "diagnostics", "devbot"]
aliases: ["prune skips vacuum", "single vacuum prune"]
---

# `devbot prune --db`: the age prune returns early, so the strip must own the VACUUM

`prune_opencode_db.py` returns as soon as the aged-session and orphan counts are both zero - **before** `_vacuum(con)`. That is fine for an age-only prune, but it breaks any design that defers reclaiming to it: `bin/prune.sh` first called the strip helper with `--no-vacuum` and relied on the age prune's VACUUM, which never ran when nothing was aged - the common case right after a strip.

Fix (PR [#61](https://github.com/GET-E/dev-bot/pull/61)): one helper owns both passes. `prune_opencode_db.py --strip-diagnostics` imports `plan_strip`/`apply_plan` from `strip_opencode_diagnostics.py`, runs them on the same connection before the age prune, and only then decides there is nothing to do - `old == 0 and old_v2 == 0 and orphans == 0 and stripped == 0`. Exactly one VACUUM follows, and the file shrinks even when every session is recent.

Two constraints worth keeping:

- The strip pass must sit inside the helper's own `sqlite3.Error` handling (fail-open). A malformed JSON payload raises inside `json_type`, and an uncaught traceback would break the documented exit-0 contract; stop before the age prune and tell the user a re-run finishes it.
- Batch size must be bounded by bytes (`length(CAST(data AS BLOB))`), not by rows: one payload can be ~18 MB, so 250 rows is ~4.5 GB per transaction.

Tests: `bin/tests/strip_opencode_diagnostics_tests.bats` (13 BATS) and `src/harnesses/opencode/test_strip_opencode_diagnostics.py` (7 unit).
