---
date: 2026-09-24
keywords: ["python", "rope", "extract", "offsets", "refactoring"]
trigger-on: ["rope-refactoring", "rope-extract"]
---

## rope extract takes character offsets; a selection that ends mid-word is rejected

`ExtractMethod(project, resource, start_offset, end_offset)` and `ExtractVariable(...)` take **character** offsets. Selecting by line means converting to offsets yourself, and two traps follow: an end column is **inclusive**, so the exclusive offset is `line_start + end_col` (not `end_col - 1`) — off by one and the selection truncates to `price * qt`; and any selection whose boundary lands mid-word raises `RefactoringError: Should extract complete statements.` (from the internal `_is_region_on_a_word` check), which reads like a statement-shape error but is really a boundary error. A whole-line selection should end at the line's content end (newline excluded). `ExtractVariable` may also refuse a multi-line region (`Should extract complete statements`).
