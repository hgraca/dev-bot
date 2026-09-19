---
date: 2026-09-20
keywords: ["tool-grades-report", "quadrants", "thresholds", "windowing"]
see: ["ADRs/20260918231739-02-stats-reads-tool-grades-csv.md", "PDRs/20260920000940-tool-grades-report-purpose-and-quadrant-semantics.md"]
---

## Tool Grades reports spread and a quality x demand quadrant grid

The section ranked tools on a bare average, which let one lucky session top the chart and gave no signal for keep/improve/remove. Each tool now carries `min` (worst grade in scope) and `stdev` (population spread, withheld below three uses), and every tool is placed on a quality x demand grid — high-avg x many-uses top-left — bucketed `workhorse` / `specialist` (keepers), `improve` (needed but poor) and `unproven` (too few uses to judge); never-used tools render below the grid, on neither axis.

`QUALITY_THRESHOLD = 3.5` is the midpoint between the rubric's 3 ("poor", per `POOR_GRADES`) and 4 ("good"). At 3.0 four predominantly-3 tools rendered as keepers while the same report listed them under Poor ratings. Demand is relative, so the bar is `max(3, ceil(median(use counts > 0)))`, recomputed per report and printed in the section intro.

Grades are windowed by the parent's `--days`: `rows` counts rows in scope and in the window, while `total_rows` and `sessions` stay all-time as the denominator the window is shown against. A row with no parseable `datetime` is kept only when the dated rows immediately before and after it are both inside the window, otherwise dropped. A single combined usage x grade score was rejected: it ranks a rarely-needed-but-excellent specialist near zero.
