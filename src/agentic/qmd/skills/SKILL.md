---
name: devbot:qmd
description: "Reference for the qmd (Quick Markdown) memory-search engine — BM25-only, used internally by the memory module. Consult when you need to understand qmd's index/collections or maintain it. For memory recall use the search-memories tool; the qmd CLI is not available to agents."
---

# QMD — Quick Markdown Search (engine reference)

qmd is one of the two memory-search engines dev-bot can use, active only when
`memory_search_provider` is `"qmd"` in `.devbot.global.jsonc` (default is
`mdctx`). In dev-bot it is **BM25-only**: no GGUF models are downloaded and no
embeddings are computed (ADR `20260913072905-qmd-bm25-only-no-model-downloads`).

> **Agents do not invoke qmd directly.** Memory recall goes through the
> **`search-memories`** tool (see `devbot:search-memory`) — it wraps qmd's
> `search` (BM25) path and scopes to the current project vault plus the shared
> global store. There is no qmd tool in the palette (the qmd MCP server was
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

The project collection is scoped to **`.agents/memory/latent/`** by design —
the vault's _promoted_ knowledge (ADRs, PDRs, learnings, global notes). Scratch
content under `.agents/memory/thinking/` is deliberately **not indexed**: it is
ephemeral WIP that is either promoted to `latent/` or deleted, so indexing it
would return stale or throwaway matches.

- A note that exists only under `thinking/` will **not** be found until it is
  promoted to `latent/`.
- If you must search scratch/thinking content, use `grep` on
  `.agents/memory/thinking/` — qmd is the wrong tool for it.

Add a second collection explicitly and pass its name to every search:

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
