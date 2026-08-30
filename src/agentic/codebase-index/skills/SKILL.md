---
name: devbot:codebase-index
description: "Semantic code search, implementation lookup, call graph, and codebase indexing via Ollama embeddings. Use this skill whenever finding code by meaning rather than keywords — e.g. 'where is the payment handler', 'who calls this function', 'how do these parts connect'. Run index_codebase before the first search in a session."
---

# Codebase Index

Semantic code search powered by Ollama embeddings (`nomic-embed-text`). Provides 5 MCP tools for searching, peeking, and tracing code.

## When to Use

| Situation                                               | Tool                           |
| ------------------------------------------------------- | ------------------------------ |
| First session or after large changes, before any search | `index_codebase`               |
| Find code by meaning, not keywords                      | `codebase_search`              |
| Quick metadata lookup (file, line, name, type)          | `codebase_peek`                |
| Find where a function/method is defined                 | `implementation_lookup`        |
| Understand callers or callees of a function             | `call_graph`                   |
| Find duplicate or similar code                          | `find_similar`                 |
| Manual index health check                               | Run `codebase-index.sh status` |

## MCP Tools

### `index_codebase` — (Re)build index

- Call at session start or after large file edits.
- **Incremental** — only changed files re-embedded.
- Supports `estimateOnly: true` to preview cost without building.

### `codebase_search` — Semantic code search

- Returns full code content with surrounding context.
- Use natural language: "where is authentication logic?" not "getAuth()".
- Filter: `fileType`, `directory`, `chunkType`, `contextLines`.

### `codebase_peek` — Metadata-only lookup

- Returns only metadata (file, line, name, type, chunkType).
- Saves ~90% tokens vs `codebase_search`. Use when you just need locations.

### `implementation_lookup` — Find definitions

- Prefers real implementation files over tests, docs, examples, fixtures.

### `call_graph` — Trace callers/callees

- Query by function name + optional `symbolId` for callees direction.

### `find_similar` — Duplicate/similar code detection

- Pass code snippet, get similar code across codebase.

### `index_status` — Health check

- Shows indexed files count, chunk count, last index time, embedding provider.

### `index_health_check` — Clean stale entries

- Removes entries from deleted files. Check health first.

## Indexing Workflow

1. **Session start**: The index auto-indexes on startup (`autoIndex: true`) — incremental, only changed files re-embedded.
2. **During session**: Search with `codebase_search`/`codebase_peek`. When the index is stale (e.g. after a branch switch or merge), a search triggers an incremental rebuild automatically.
3. **After large edits**: Call `index_codebase` to re-embed changed files immediately.
4. **Manual health check**: `bash src/agentic/codebase-index/tools/codebase-index.sh status`.

## CLI Manual Fallback

```bash
# Status
bash src/agentic/codebase-index/tools/codebase-index.sh status

# Index (full rebuild)
bash src/agentic/codebase-index/tools/codebase-index.sh index

# Search
bash src/agentic/codebase-index/tools/codebase-index.sh search "your query"

# Peek
bash src/agentic/codebase-index/tools/codebase-index.sh peek "your query"
```

## Notes

- Index respects `.gitignore` natively — no client-side filtering needed.
- Requires Ollama with `nomic-embed-text` model at `http://localhost:18434`, or wherever the ollama API is.
- MCP server config at `.opencode/codebase-index.json` in project root.
