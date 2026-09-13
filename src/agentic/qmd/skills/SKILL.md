---
name: devbot:qmd
description: "Use this skill whenever the user asks to search notes, find documents, or look up information in markdown knowledge bases using QMD — keyword (BM25) search over notes, docs, and transcripts. Use it even if they do not say 'qmd'."
---

# QMD — Quick Markdown Search

Local search engine for markdown content. Use when you need to find documents, search notes, or look up information in the project's `.agents/memory/` vault.

> **Engine note:** qmd is one of the two memory-search engines dev-bot can use.
> It is active only when `memory_search_provider` is `"qmd"` in
> `.devbot.global.jsonc` (default is `mdctx`). Whichever engine is selected,
> **memory search routes through `search-memories`** (see
> `devbot:search-memory`); this skill documents qmd's native surface
> (collections, index maintenance, BM25 search) for engine-specific work.
>
> **qmd is BM25-only.** dev-bot does not download qmd's GGUF models and does not
> run `qmd embed` (ADR `20260913072905-qmd-bm25-only-no-model-downloads`). The
> semantic commands (`qmd query` with `vec`/`hyde`/`expand`, `qmd embed`,
> `qmd pull`) are out of scope and would trigger a model download — do not use
> them. Use `qmd search` (BM25) or the `search-memories` tool instead.

## When to Use

| Situation                                                             | Tool                    |
| --------------------------------------------------------------------- | ----------------------- |
| Need to find a specific memory, ADR, PDR, or pattern note             | **QMD**                 |
| Searching the `.agents/memory/latent/` vault by keyword               | **QMD**                 |
| Looking up project documentation or decisions from the knowledge base | **QMD**                 |
| Need to check if a concept has been documented before writing it      | **QMD**                 |
| Browsing or exploring the memory vault structure                      | QMD `get` / `multi-get` |

**Prefer QMD `search` (BM25) over `grep` for memory vault searches.** QMD understands markdown structure, maintains an index, and returns ranked results with snippets. For semantic recall, use the memory module's `search-memories` tool — not qmd's model-backed query.

## How to Call

```
qmd.mcp.sh <command> [args...]
```

### Key Commands

| Command                               | Description                                | Example                                                             |
| ------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------- |
| `status`                              | Show QMD health and registered collections | `qmd.mcp.sh status`                                                 |
| `search "<keywords>"`                 | BM25 keyword search                        | `qmd.mcp.sh search "CAP theorem consistency"`                       |
| `get <id-or-path>`                    | Retrieve document by docid or path         | `qmd.mcp.sh get "#abc123"`                                          |
| `multi-get <glob>`                    | Batch retrieve multiple docs               | `qmd.mcp.sh multi-get "journals/2026-*.md"`                         |
| `update`                              | Update the search index                    | `qmd.mcp.sh update`                                                 |
| `collection add <path> --name <name>` | Register a collection                      | `qmd.mcp.sh collection add .agents/memory/latent --name my-project` |

### Path Resolution

When using QMD, always feed `qmd_get` with the `file` value directly from `qmd_search` results rather than guessing paths. QMD returns results with relative paths — use these directly. If you try to construct the path yourself, it may resolve to the wrong location.

**Correct**: `qmd_get file="#abc123"` (use docid from search results)
**Incorrect**: `qmd_get file="docs/summary.md"` (guessing paths)

### Pipe Mode

```
echo "rate limiter burst" | qmd.mcp.sh
```

## Output Format

```
## QMD output

\`\`\`
<qmd result>
\`\`\`
```

## Setup

```bash
qmd collection add .agents/memory/latent --name my-project
qmd update
```

### Collection scope

The project QMD collection is scoped to **`.agents/memory/latent/`** by
design — the vault's _promoted_ knowledge (ADRs, PDRs, learnings, global
notes). Scratch content under `.agents/memory/thinking/` is deliberately
**not indexed**: it is ephemeral WIP that is either promoted to `latent/`
or deleted, so indexing it would return stale or throwaway matches.

Consequences to be aware of when searching:

- A note that exists only under `thinking/` will **not** be found by QMD
  until it is promoted to `latent/`.
- `qmd update` refreshes the index only when the `latent/` directory exists
  (see `src/agentic/qmd/update.sh`).
- If you need to search scratch/thinking content, use `grep` on
  `.agents/memory/thinking/` instead — QMD is the wrong tool for it.

To add a second collection for scratch notes, register it explicitly and
pass its name to every search:

```bash
qmd collection add .agents/memory/thinking --name my-project-thinking
qmd search "..." --collection my-project-thinking
```

## Examples

```
# Check QMD status
qmd.mcp.sh status

# Keyword search
qmd.mcp.sh search "rate limiter burst"

# Retrieve a document by ID
qmd.mcp.sh get "#abc123"

# Pipe mode
echo "refund processing flow" | qmd.mcp.sh
```

## CLI

Refer to the `tools/qmd.mcp.sh` wrapper for the CLI entrypoint. For memory recall, use the `search-memories` tool (BM25 keyword search — no GPU/LLM models required); it scopes to the current project vault plus the shared global store.
