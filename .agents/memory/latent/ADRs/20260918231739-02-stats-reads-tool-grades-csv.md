---
date: 2026-09-18
keywords: ["devbot-stats", "tool-grades", "tool_grades", "render-stats"]
see: ["PDRs/20260918231739-01-stats-scope-all-projects-default.md"]
---

## devbot stats reads the grade matrix via a parent-injected tool_grades block

`devbot stats` now renders a `## Tool Grades` section from the install-level `.agents/logs/tools-grades.csv` (written by `devbot:grade-tools`). The CSV is harness-agnostic and install-level, so it is **not** read by a harness adapter: `bin/stats.sh` (the parent) reads it through `src/_shared/tool_grades.py`, which folds an optional `tool_grades` block into the canonical JSON after validation, and `src/_shared/render_stats.py` renders it. The canonical `schema` stays `1` (additive optional key) and adapters must never emit `tool_grades`. The block carries `rows` (in scope), `total_rows`, distinct `sessions`, and `tools[]` — every tool column from the CSV, each with `avg` (over rows where the tool was used, grade ≥ 1), `uses`, and de-duplicated 1–3 grade `reasons`; tools never used are listed with `avg: null` and `uses: 0`, sorted after the used ones by descending average. A missing CSV is silent; a malformed or unreadable one warns on stderr and degrades to the ungraded report. The CSV path is overridable with `DEV_BOT_STATS_GRADES_CSV`.
