---
layout: page
title: MCPs
description: MCP servers DevBot wires into OpenCode and Claude Code.
nav_section: docs
---

# MCPs

DevBot wires **12 MCP servers** into the agent tool palette. Each lives in a module's `mcp.opencode.json` and is auto-registered during `devbot init`. The list below is generated via `devbot list mcps -a` (includes disabled modules):

| Module          | MCP server        | Provides                                                      |
| --------------- | ----------------- | ------------------------------------------------------------- |
| chrome-devtools | `chrome-devtools` | Browser inspection, console, network, performance, Lighthouse |
| codebase-index  | `devbot:codebase-index`  | Semantic code search, implementation lookup, call graph       |
| context7        | `context7`        | Version-accurate library/framework documentation              |
| graphify        | `devbot:graphify`        | Codebase knowledge graph querying                             |
| jetbrains       | `jetbrains`       | IDE integration — inspections, debugging, database tools      |
| playwright      | `playwright`      | Browser automation and E2E testing                            |
| qmd             | `devbot:qmd`             | Markdown knowledge-base search (semantic + keyword)           |
| react           | `next-devtools`   | Next.js runtime diagnostics                                   |
| signoz          | `signoz`          | Observability — dashboards, alerts, queries, investigation    |
| svelte          | `svelte`          | Svelte framework integration                                  |
| tools-mcp       | `devbot-tools`    | DevBot tool scripts as MCP tools (see below)                  |
| websearch       | `websearch`       | Web search via Exa API                                        |

## devbot-tools MCP tools

The `devbot:tools-mcp` module's `devbot-tools` MCP server is the only MCP whose tools come from DevBot itself — it exposes the DevBot tool scripts as MCP tools, each self-describing via its `mcp-meta` subcommand. The 11 tools are generated via `devbot list tools -a`:

| Module              | Tool                | Description                                                                                                                                                                                                                           |
| ------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| agent-communication | agent-communication | Validate that an assistant message ends with a terminal status marker ([FINISHED], [BLOCKED], [NEEDS_INPUT], [PARTIAL])                                                                                                               |
| docs                | use-case-map        | Generate a UseCaseMap architecture diagram JSON from a PHP codebase. Traces call chains from entry points through commands, handlers, ports, adapters, and HTTP clients.                                                              |
| format-json         | format-json         | Format JSON and JSONC files with consistent 2-space indentation via prettier                                                                                                                                                          |
| format-md           | format-md           | Format markdown files with consistent formatting via prettier                                                                                                                                                                         |
| format-yml          | format-yml          | Format YAML files with consistent 2-space indentation via prettier                                                                                                                                                                    |
| git                 | git-report          | Capture a snapshot of the current git state: current branch, default branch, recent commits, working tree status, staged diff, commits unique to the current branch, and index integrity                                              |
| k8s                 | lint-k8s            | Audit Kubernetes, Kustomize, or Helm manifests using kubeconform (schema validation) and kube-linter (best practices)                                                                                                                 |
| memory              | reindex-memories    | Rebuild the QMD memory index by running qmd update && qmd embed in the background (fire-and-forget). Coalesces concurrent runs via a pidfile. Pass the argument 'status' to check whether a reindex is running without launching one. |
| memory              | search-memories     | Search the memory vault and return full file bodies. Fast keyword (BM25) search across QMD-indexed memories — no GPU or LLM models required.                                                                                          |
| qmd                 | qmd                 | Search and navigate markdown knowledge bases using QMD. Supports query (semantic), search (BM25), get, multi-get, update, embed, and collection/context management.                                                                   |
| tree                | tree                | Display directory structure as a tree. Accepts one or more paths. Returns output in markdown or plain text.                                                                                                                           |

All other MCP servers are external packages whose tool sets are defined by the server itself (e.g. `chrome-devtools_*`, `playwright_*`, `context7_*`).
