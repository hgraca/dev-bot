---
title: "Graphify"
description: "Structural knowledge graph auto-built from your codebase."
skills: ["graphify"]
hooks: ["graphify-commit-check", "graphify-commit-detect", "graphify-session-update"]
tools: ["graphify", "graphify-commit-trigger", "graphify-serve-shim", "graphify-update-bg", "start-graphify-mcp"]
mcps:
  graphify: "Codebase knowledge graph querying"
---

Graphify builds a persistent knowledge graph from your codebase — queries run against AST data, no API calls needed.

## What it does

- **Auto-builds** a graph on every commit (or every 30 minutes)
- **God nodes** identify the most connected symbols in the codebase
- **Community detection** discovers natural module boundaries
- **Cross-file relationships** trace dependencies and call graphs
- **Query tools**: `graphify query`, `graphify path`, `graphify explain`

## How agents use it

Agents query graphify to understand code structure — trace how a function connects to others, find all callers of a method, or discover which modules would be affected by a change.

**MCP `project_path`:** the graphify MCP server appends `graphify-out/graph.json`
to the `project_path` you pass it — always pass the **project root**, never a
`…/graphify-out` path (that double-joins and errors, audit-51 NOTE). The CLI
(`graphify query/path/explain`) discovers the graph itself.

## Local model

Uses Ollama embeddings for semantic understanding. No cloud API calls.

## Configuration

No project configuration is required.

Graphify indexes only `src/` and/or `app/` — never the project root. The scope is
enforced by a managed `SOURCE SCOPE` block in the project's `.graphifyignore`,
written on `devbot init`/`reinit` and re-applied on `devbot up`. A project with
neither directory indexes nothing, so disable the module there (`"graphify": false`
in `.devbot.project.jsonc`). The negations are bare (`!src`): graphify's parser
matches the leading-slash form (`!/src`) against nothing, silently indexing zero
files.

The block is terminal — everything from its `SOURCE SCOPE (auto)` marker to the
end of the file is managed, so hand-written patterns belong above it.

When `graphify-out/graph.json` is missing, `init`/`up` write an empty placeholder
graph so the MCP server can start before the first build.

The AST cache under `graphify-out/cache` is pruned on `devbot up` — entries not
modified in more than **7 days** are removed. Override the retention window with
the `GRAPHIFY_CACHE_MAX_AGE_DAYS` environment variable (e.g.
`GRAPHIFY_CACHE_MAX_AGE_DAYS=30`).

## See also

- [Codebase Index](/modules/agentic/codebase-index) — semantic code search
- [QMD](/modules/agentic/qmd) — knowledge vault search
