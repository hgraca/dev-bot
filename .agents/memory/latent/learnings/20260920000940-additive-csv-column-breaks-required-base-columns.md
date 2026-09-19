---
date: 2026-09-20
keywords: ["tools-grades-csv", "schema-migration", "base-columns"]
---

# An additive CSV column is a breaking change when the reader requires every base column

Adding `actor` to `BASE_COLUMNS` in `record-grades.py` (the writer) also added it to the reader's `src/_shared/tool_grades.py` copy, whose `build_tool_grades` rejects any matrix missing a base column. Every existing install therefore lost the entire Tool Grades section — `WARN: … is not a tool-grades CSV (missing actor)` and `block is None` — until its next grade write, even though nothing about the old rows was unreadable.

The fix is a split, not a migration: the reader checks a separate `REQUIRED_COLUMNS` (what it actually uses) while `BASE_COLUMNS` keeps listing `actor`, so the column is classified as a base column rather than a tool column (which `write_csv` would coerce to `0`). A unit test and an end-to-end BATS test now read a valid four-column matrix.

The trap generalises: `BASE_COLUMNS` is duplicated across the writer and the reader and synced **by source comment only** — no shared import, no schema version. A contract test that loads both modules by path and compares `BASE_COLUMNS` + `DATETIME_FORMAT` now guards it, and caught the reader drifting on its first run. When the copies diverge the failure is silent (a dropped report section), never an error.
