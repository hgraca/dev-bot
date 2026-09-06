---
name: devbot:codebase-index
description: "Codebase understanding via the codebase-memory engine — structural code search, call-graph tracing, architecture overview, git-diff impact analysis, and Cypher graph queries backed by a persistent tree-sitter knowledge graph. Use this skill whenever finding code by structure or meaning — e.g. 'who calls this function', 'how do these parts connect', 'what is the architecture', 'what does this diff affect'. The engine this skill documents is selected by the codebase_index_provider config key; the skill name stays devbot:codebase-index whichever engine is active."
---

# Codebase Memory (codebase-memory-mcp engine)

Fast codebase intelligence backed by a persistent tree-sitter knowledge graph
(functions, classes, call chains, HTTP routes, cross-service links). The native
binary bundles its own nomic embeddings — **no Ollama, no API key, no GPU, no
Docker**. Indexes to `~/.cache/codebase-memory-mcp/` and serves MCP tools for
searching, tracing, and analysing the graph.

## When to Use

| Situation                                                    | Tool                                   |
| ------------------------------------------------------------ | -------------------------------------- |
| First session or after large changes, before graph queries   | `index_status` → `index_repository`    |
| Understand graph schema (node/edge counts) before querying   | `get_graph_schema`                     |
| Structural / BM25 / semantic search across the graph         | `search_graph`                         |
| Grep-like text search within indexed files                   | `search_code`                          |
| Who calls a function / what it calls (BFS, depth 1-5)        | `trace_path` (alias `trace_call_path`) |
| Architecture overview: languages, packages, routes, hotspots | `get_architecture`                     |
| Git diff → affected symbols + blast radius                   | `detect_changes`                       |
| Read a function's source by qualified name                   | `get_code_snippet`                     |
| Arbitrary relationship queries (read-only Cypher subset)     | `query_graph`                          |
| Persist architecture decisions across sessions               | `manage_adr`                           |

## MCP Tools

### `index_repository` — Build/refresh the index

- Call after indexing a project for the first time, or to force a refresh.
- The background watcher (`auto_watch`, default true) keeps it fresh via git-based
  change detection afterwards — no manual reindex needed for normal edits.
- **Bundled embeddings**: no Ollama model pull, no `index_codebase`-style cost
  preview needed.

### `get_graph_schema` — Understand the graph first

- Run this before deep queries: node/edge counts, relationship patterns,
  property definitions per label.
- Node labels: `Project`, `Package`, `Folder`, `File`, `Module`, `Class`,
  `Function`, `Method`, `Interface`, `Enum`, `Type`, `Route`, `Resource`.
- Edge types include `CALLS`, `CALL_REFERENCE`, `IMPORTS`, `IMPLEMENTS`,
  `INHERITS`, `HTTP_CALLS`, `ASYNC_CALLS`, `DATA_FLOWS`, `EMITS`, `LISTENS_ON`.

### `search_graph` — Structural/semantic search

- Regex name patterns, label filters, degree bounds, file scoping.
- Ranked semantic rows page with `semantic_offset`/`semantic_limit`; structural
  rows with `offset`/`limit`.
- Use to discover qualified names before `get_code_snippet`.

### `search_code` — Text search inside indexed files

- Graph-augmented grep over indexed files only. Pages with
  `result_limit`/`result_offset`; raw lines come back match-centred.

### `trace_path` — Call-graph traversal

- BFS: who calls a function (inbound) and what it calls (outbound), depth 1-5.
- The graph answers "what calls ProcessOrder?" without grep/read loops.

### `get_architecture` — Big picture

- Languages, packages, entry points, routes, hotspots, boundaries, layers,
  clusters — one call.

### `detect_changes` — Impact analysis

- Maps uncommitted git diff to affected symbols with risk classification and
  blast radius. Run before refactors to see what a change touches.

### `query_graph` — Cypher-like queries

- Read-only openCypher subset: `MATCH`, `WHERE`, `RETURN`, `ORDER BY`, `LIMIT`,
  `UNWIND`, `UNION`, variable-length paths, regex `=~`, `EXISTS { }` subqueries.
- Dead-code example: `MATCH (f:Function) WHERE NOT EXISTS { (f)<-[:CALLS]-() }
RETURN f.name` — anything outside the subset fails with a clear `unsupported`
  error rather than returning empty results.

### `manage_adr` — Architecture Decision Records

- `get` reads, `update` replaces the document, `set_sections` rewrites only the
  named sections byte-preserving, `sections` lists headings.

### Project lifecycle tools

- `index_status` — check a project's indexing status.
- `list_projects` / `delete_project` — list / remove indexed projects.

## Workflow

1. **Session start**: the engine auto-indexes on first connection (`auto_index`).
   Check with `index_status`; force with `index_repository` when the index is
   stale (branch switch, merge, large pull).
2. **Before queries**: `get_graph_schema` to know what labels/edges exist.
3. **During session**: `search_graph` for discovery → `trace_path` for call
   chains → `get_code_snippet` to read exact source → `query_graph` for
   relationship questions the named tools don't cover.
4. **Before a refactor**: `detect_changes` to map the blast radius of uncommitted
   work.

## Notes

- **Never run `codebase-memory-mcp install` / `uninstall` from devbot context** —
  the engine's own installer edits client configs and installs agents/skills.
  The devbot module handles registration (MCP manifests) and lifecycle (npm
  global install); settings are managed with `codebase-memory-mcp config set`
  if needed (e.g. `auto_index`, `auto_watch`).
- Index data lives under `~/.cache/codebase-memory-mcp/`. An optional
  `.codebase-memory/graph.db.zst` artifact can be committed to a repo so
  teammates skip reindexing — treat it as a deliberate, low-cadence commit.
- Keep heavy generated dirs (`graphify-out/`, `node_modules/`, `no-vcs/`)
  gitignored so the watcher and index stay lean.
- Requires Node.js >= 18 (the npm package); the native runtime is installed and
  verified by the npm package on first use.
