---
date: 2026-09-23
keywords: ["rector", "dry-run", "exit-code"]
trigger-on: ["rector-dry-run-exit-code"]
---

## Rector exits 2 (not 0) when a dry run finds changes

`rector process --dry-run` exits **2** when it finds changes it would apply, **0** when there is nothing to do, and **1** on error. Tooling that treats any non-zero exit as failure therefore reports a perfectly good plan as an error, even though the JSON body is valid and carries `totals.changed_files`. Verified on Rector 2.6.7. Map it explicitly: success = `rc == 0`, or `rc == 2` in dry-run with `totals.errors == 0`. Related trap on the same command: a **config** failure is reported differently again — stdout `{"fatal_errors": [...]}` with exit 1 (e.g. an invalid class name) — and must be surfaced explicitly, or the caller sees only "exited 1" with no diagnosis at all.
