---
date: 2026-08-18
keywords: ["css", "table-fixed", "column-width", "table-layout", "sticky-column"]
trigger-on: ["table-layout-fixed-width-distribution"]
---

## table-layout: fixed distributes spare width proportionally over every column

In `table-layout: fixed`, when the table's used width (e.g. `width: 100%`) is larger than the sum of the columns' explicit widths, the extra space is not kept by auto-width columns — it is distributed proportionally over ALL columns, including ones with a fixed width. Symptom seen in `CompareMatrixTable`: a sticky question column set to 200px grew to ~840px as soon as every other column was collapsed to a narrow fixed width. Columns with `width: auto` absorb the remaining space instead. Fix: always keep at least one auto-width column — a trailing empty spacer `<col style={{ width: 'auto' }}>` with empty `<th>`/`<td>` cells absorbs the surplus so fixed-width columns (question, collapsed hotels) hold their exact px. Verify per column with `getBoundingClientRect()` after collapsing/expanding.
