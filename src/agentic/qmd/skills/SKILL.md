---
name: devbot:qmd
description: "Use this skill whenever the user asks to search notes, find documents, or look up information in markdown knowledge bases using QMD — semantic and keyword search over notes, docs, and transcripts. Use it even if they do not say 'qmd'."
---

# QMD — Quick Markdown Search

Local search engine for markdown content. Use when you need to find documents, search notes, or look up information in the project's `.agents/memory/` vault.

## When to Use

| Situation                                                               | Tool                    |
| ----------------------------------------------------------------------- | ----------------------- |
| Need to find a specific memory, ADR, PDR, or pattern note               | **QMD**                 |
| Searching the `.agents/memory/latent/` vault semantically or by keyword | **QMD**                 |
| Looking up project documentation or decisions from the knowledge base   | **QMD**                 |
| Need to check if a concept has been documented before writing it        | **QMD**                 |
| Browsing or exploring the memory vault structure                        | QMD `get` / `multi-get` |

**Prefer QMD over `grep` for memory vault searches.** QMD understands markdown structure, supports semantic (vector) search, and returns ranked results with snippets.

## How to Call

```
qmd.mcp.sh <command> [args...]
```

### Key Commands

| Command                               | Description                                | Example                                                             |
| ------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------- |
| `status`                              | Show QMD health and registered collections | `qmd.mcp.sh status`                                                 |
| `query "<text>"`                      | Auto-expand + rerank search                | `qmd.mcp.sh query "how does the rate limiter work"`                 |
| `search "<keywords>"`                 | BM25-only keyword search                   | `qmd.mcp.sh search "CAP theorem consistency"`                       |
| `get <id-or-path>`                    | Retrieve document by docid or path         | `qmd.mcp.sh get "#abc123"`                                          |
| `multi-get <glob>`                    | Batch retrieve multiple docs               | `qmd.mcp.sh multi-get "journals/2026-*.md"`                         |
| `update`                              | Update the search index                    | `qmd.mcp.sh update`                                                 |
| `collection add <path> --name <name>` | Register a collection                      | `qmd.mcp.sh collection add .agents/memory/latent --name my-project` |

### Path Resolution

When using QMD, always feed `qmd_get` with the `file` value directly from `qmd_query` results rather than guessing paths. QMD returns results with relative paths — use these directly. If you try to construct the path yourself, it may resolve to the wrong location.

**Correct**: `qmd_get file="#abc123"` (use docid from search results)
**Incorrect**: `qmd_get file="docs/summary.md"` (guessing paths)

### Pipe Mode

```
echo "query from stdin" | qmd.mcp.sh
```

## Output Format

```
## QMD output

\`\`\`
<qmd result>
\`\`\`
```

## Structured Search (MCP `query` approach)

For complex queries, use the MCP `query` tool (via OpenCode's MCP palette) which supports structured search documents:

```json
{
    "searches": [
        { "type": "lex", "query": "CAP theorem consistency" },
        { "type": "vec", "query": "tradeoff between consistency and availability" }
    ],
    "collections": ["my-project", "global"],
    "limit": 10
}
```

### Query Types

| Type     | Method      | Input                                           |
| -------- | ----------- | ----------------------------------------------- |
| `lex`    | BM25        | Keywords — exact terms, names, code identifiers |
| `vec`    | Vector      | Natural language question                       |
| `hyde`   | Vector      | Hypothetical answer (50-100 words)              |
| `expand` | Auto-expand | Single-line query, LLM generates variations     |

### Writing Good Queries

**lex (keyword):** 2-5 terms, no filler words. Exact phrase with quotes: `"connection pool"`. Exclude with minus: `performance -sports`. Code identifiers work: `handleError async`.

**vec (semantic):** Full natural language question. Be specific: `"in the payment service, how are refunds processed"`.

**hyde (hypothetical):** Write 50-100 words of what the _answer_ looks like. Use the vocabulary you expect in the result.

**expand (auto-expand):** Use a single-line query. Lets the local LLM generate lex/vec/hyde variations.

### Intent (Disambiguation)

When a query term is ambiguous, add `intent` to steer results:

```json
{
    "searches": [{ "type": "lex", "query": "performance" }],
    "intent": "web page load times and Core Web Vitals"
}
```

### Collection Filtering

```json
{ "collections": ["my-project"] }
{ "collections": ["my-project", "global"] }
```

Omit to search all collections. The `search-memories` tool always includes `dev-bot-global` alongside the project collection.

### Structured Queries

Multi-line `lex:`/`vec:`/`hyde:` documents are accepted directly by the CLI:

```bash
qmd query 'lex:exact terms here
vec:natural language question here'
```

## Setup

```bash
qmd collection add .agents/memory/latent --name my-project
qmd embed
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
pass its name to every query:

```bash
qmd collection add .agents/memory/thinking --name my-project-thinking
qmd query "..." --collection my-project-thinking
```

## Examples

```
# Check QMD status
qmd.mcp.sh status

# Simple keyword search
qmd.mcp.sh search "rate limiter burst"

# Semantic query
qmd.mcp.sh query "how does authentication work in this project"

# Retrieve a document by ID
qmd.mcp.sh get "#abc123"

# Pipe mode
echo "refund processing flow" | qmd.mcp.sh
```

## CLI

Refer to the `tools/qmd.mcp.sh` wrapper for the CLI entrypoint. For structured queries from agents, use the `search-memories` tool (BM25 keyword search — no GPU/LLM models required) or the `qmd mcp` MCP server.

## Semantic search needs GPU VRAM headroom

`query` (auto-expand + rerank) runs qmd's own llama models on the GPU. When
the GPU is oversubscribed (other models/processes sharing VRAM, e.g. a 6 GB
laptop GPU), qmd can fail to create an embedding context and the MCP tool may
return a **bare empty result** — indistinguishable from "nothing found". If a
`query` returns nothing unexpectedly: check `qmd doctor` for an
embedding-context warning, and fall back to `search "<keywords>"` (BM25, no
GPU) or `query` with explicit `searches:[{type:"lex",...}]` + `rerank:false`.
The `search-memories` devbot-tools tool is the same BM25 path.
