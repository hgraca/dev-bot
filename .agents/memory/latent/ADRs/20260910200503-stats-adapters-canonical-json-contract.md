---
date: 2026-09-10
keywords: ["devbot", "stats", "adapter", "canonical-json", "harness"]
---

## `devbot stats` adapters: canonical JSON between parent CLI and per-harness child

`devbot stats` is harness-agnostic: the parent (`bin/stats.sh`) detects the harness, runs `src/harnesses/<harness>/stats.sh`, validates its JSON, and renders Markdown via `src/_shared/render_stats.py`. Each adapter gathers data and prints a canonical JSON object (schema v1: `schema`, `harness`, `days`, `scope`, `scope_label`, `generated_at`, `cost_kind`, `tools[]`, `mcp_servers[]`, optional `tool_arguments`). The parent validates `schema == 1` plus required keys; all presentation stays in the parent. Rationale: harnesses differ sharply in data source (opencode = SQLite; claudecode = JSONL transcripts) and in what they can report (opencode has per-step cost, claudecode has tokens only), so isolating extraction behind one adapter per harness keeps the report uniform and makes a new harness a single drop-in script. Cost is even-split across a step's tools on opencode (`cost_kind: estimated`); the MCP-share column is relative to MCP calls, not all tool calls. Argument aggregation (`tool_arguments`) normalises bash commands to `program subcommand`, stripping leading `cd … &&` / `cd …` lines and comment lines (`src/_shared/stats_args.py`).
