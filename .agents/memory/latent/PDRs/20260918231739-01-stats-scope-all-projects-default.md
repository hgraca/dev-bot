---
date: 2026-09-18
keywords: ["devbot-stats", "scope", "tool-grades", "cli"]
see: ["ADRs/20260918231739-02-stats-reads-tool-grades-csv.md"]
---

## devbot stats reports every project by default

Stakeholder decision (2026-09-18): `devbot stats` scopes to every project by default and gains `--project=DIR` to restrict the report to one project directory; `--all` is kept only as an accepted alias. Rationale: the previous default (the current project) hid most of the grade matrix — MCP servers graded 0 in one project's row disappeared from the report entirely, and the command is meant to show cross-project tool quality. Both harness stats adapters now aggregate every recorded project unless `--project` narrows them, and the Tool Grades section follows the same scope. The reversal is cheap (one flag default), but the docs and the adapter contract (`scope: all|current`) both encode the new default.
