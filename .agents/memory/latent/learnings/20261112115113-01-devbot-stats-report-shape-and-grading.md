---
date: 2026-11-12
keywords: ["devbot-stats", "tool-grades", "render-stats", "never-used", "mcp-usage"]
---

# `devbot stats` renders some sections conditionally and grades the CSV, not calls

## What is always there

`src/_shared/render_stats.py` always prints `## Tool Usage` and `## MCP Server Usage` (the latter
falls back to `_No MCP server usage in this window._`). `## Tool Grades` appears only when the
grade matrix has tools, and `## Tool Arguments` only when arguments were recorded. A report missing
either is empty, not broken — do not pad it with invented sections.

## MCP usage lists only servers that were used

`MCP Server Usage` is built from `server_count`, populated per used tool, so an enabled server that
was never called is absent. Take the enabled set from the harness config (`mcp` in
`opencode.jsonc`, `mcpServers` in `.mcp.json`); the tool palette shows only reachable servers and
cannot reveal one that exposed no tools.

## `Never used` is a grade bucket, not zero calls

`tool_grades.classify_bucket` returns `unused` when `uses < 1 or avg is None`, where `uses` counts
grade rows in the selected window. A tool that ran but was never graded lands there while also
appearing in Tool Usage, so `Never used` is not evidence of zero calls.

## Cost is adapter-dependent

The Cost column exists only when the adapter supplies cost: opencode emits an estimated cost per
step, while the claudecode adapter returns `cost: null` / `cost_kind: null`, so "heavy cost" is not
observable there.
