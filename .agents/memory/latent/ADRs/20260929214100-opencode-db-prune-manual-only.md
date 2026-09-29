---
date: 2026-09-29
keywords: ["opencode", "prune", "vacuum", "retention", "disk"]
supersedes: ["ADRs/20260929091830-opencode-db-prune-on-last-devbot-exit.md"]
---

## The opencode DB prune is manual-only: never on the session-exit path

ADR `20260929091830` fired `devbot prune --db` detached from `_devbot_session_release` at the install-level last-one-out point. The _trigger_ was right — that point runs exactly once, and does not depend on the docker daemon. The _operation_ was not. `prune_opencode_db.py` ends with `VACUUM`, and SQLite's `VACUUM` rewrites the **entire** database file: its cost is O(file size), not O(bytes reclaimed), single-threaded and CPU-bound.

The tool's own rotated log measured the pathology. One run deleted 5 sessions, reclaimed 7,278,592 bytes of a 7.8 GB file, and took **3m 12s**. The guard ran the prune only when _both_ the aged-session and orphan counts were non-zero, so as sessions crossed the 30-day boundary one at a time, nearly every last-session exit rewrote 7.8 GB to reclaim a few MB. The runs that were worth their cost were the exception, not the rule: the one that reclaimed 9.9 GB (4796 sessions, 17.6 GB → 7.73 GB) took 8m 21s.

Two suspects were measured and cleared, so neither is the cause: `session.time_updated` carries no index, but `session` holds 582 rows and the cutoff count ran in 0.004 s; the orphan probe (`aggregate_id NOT IN (SELECT id FROM session)`) also ran in 0.004 s. `auto_vacuum` is 0, so full `VACUUM` was the only reclaim path available — there was no cheaper substitution to reach for.

**Decision**: the prune does not run on exit. `_devbot_prune_opencode_db_detached` and its call site in `_devbot_session_release` are deleted; `devbot prune --db [days] [--force]` remains the supported entry point, run when a human decides the disk is worth reclaiming. The helper, its retention (`DEVBOT_OPENCODE_DB_RETENTION_DAYS`, default 30), the running-opencode guard, and the fail-open behaviour are unchanged — only the automatic trigger is gone. `devbot_sessions_tests.bats` carries a guard asserting the release path never shells out to `bin/prune.sh`; it was mutation-verified (it fails when the call is reintroduced).

**Rejected alternative**: keep it on the exit path but gate `VACUUM` on the reclaimable bytes (`PRAGMA freelist_count × page_size` over a threshold). That keeps a rare-but-unbounded pause attached to exiting a session, and the exit path's contract is "cheap". Manual invocation returns the same space with the cost paid deliberately, and the operator already runs it when needed.

**Consequences**: disk is no longer reclaimed without a manual `devbot prune --db`, so a machine left unattended grows to the high-water mark. `VACUUM` also needs roughly the file size again in free space in the temp directory, which is a reason to run it deliberately rather than incidentally.
