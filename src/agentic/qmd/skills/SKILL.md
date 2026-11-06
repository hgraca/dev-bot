---
name: devbot:qmd
description: "Use when you need to understand or maintain the qmd memory-search index. Triggers on 'qmd', 'memory index'."
---

# QMD — Quick Markdown Search (engine reference)

qmd is one of the two memory-search engines dev-bot can use, active only when
`memory_search_provider` is `"qmd"` in `.devbot.global.jsonc` (default is
`mdctx`). In dev-bot it is **BM25-only**: no GGUF models are downloaded and no
embeddings are computed (ADR `20260913072905-qmd-bm25-only-no-model-downloads`).

> **Agents do not invoke qmd directly.** Memory recall goes through the
> **`search-memories`** tool (see `devbot:search-memory`) — it wraps qmd's
> `search` (BM25) path and scopes to the current project vault, the shared
> global store, and any configured custom collection. There is no qmd tool in the palette (the qmd MCP server was
> removed) and direct `qmd` CLI invocation is blocked by a `guards` rule. This
> skill is a reference for the engine, not an invocation guide.

## What the memory module runs

The qmd lifecycle (`src/agentic/qmd/`) maintains the BM25 index that
`search-memories` reads:

| Step                  | Command                              | When                         |
| --------------------- | ------------------------------------ | ---------------------------- |
| Register collections  | `qmd collection add <path> --name …` | `devbot init` / `reinit`     |
| Build / refresh index | `qmd cleanup && qmd update`          | init, update, memory reindex |
| Health                | `qmd status`                         | diagnostics (human)          |

There is **no `qmd embed` and no `qmd pull`**. The semantic commands
(`query`, `vsearch`, `embed`, `pull`) are out of scope and would trigger a
model download — do not use them.

## Collection scope

The project collection is scoped to **`.agents/memory/latent/`** — the passive
memories only. `work/`, `thinking/` and `active/` are deliberately excluded so a
search recalls durable knowledge, not plans and scratch notes.

- `work/` carries active plans and backlogs: excluded from the project
  collection. Search it by registering an explicit collection (see below).
- `thinking/` carries scratch notes: excluded for the same reason.
- The shared global store is a separate collection (`dev-bot-global`).

```bash
qmd collection add .agents/memory/thinking --name my-project-thinking
qmd search "..." --collection my-project-thinking
```

## Human / script CLI

For maintenance and diagnostics outside an agent session, the wrapper
`src/agentic/qmd/tools/qmd.sh` forwards to the qmd CLI (BM25 subcommands —
`status`, `search`, `get`, `multi-get`, `update`, `collection`, `context`). It
is intentionally **not** a `.mcp.sh` tool, so the devbot-tools MCP server does
not expose it to agents.
