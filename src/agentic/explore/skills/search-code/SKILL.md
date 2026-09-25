---
name: devbot:search-code
description: "Use when you need to find code, locate a definition, or understand the architecture."
---

# Code Search

Selects right search tool for question. Different tools excel at different queries — using wrong one wastes tokens or misses results.

## When to Apply

- Finding code by meaning, keyword, or structure
- Locating definitions, callers, or implementations
- Understanding architecture or dependencies across files
- Exploring unfamiliar codebase area
- Packing code for full-context analysis

## Tool Selection

| Question type                                          | Tool                        | Why                                                                            |
| ------------------------------------------------------ | --------------------------- | ------------------------------------------------------------------------------ |
| Meaning-based search ("where is auth logic?")          | codebase engine             | The active engine's semantic search tool — see `devbot:codebase-index`         |
| Quick metadata lookup ("find payment handler")         | codebase engine             | Location-only variant when the engine has one — cheaper than full search       |
| Jump to definition ("where is validateToken defined?") | codebase engine             | Finds authoritative source, skips tests/docs/examples                          |
| Who calls this? / What does this call?                 | codebase engine             | Traces callers or callees by function name                                     |
| Find similar code (duplicate detection, refactoring)   | codebase engine             | Similarity search over the codebase                                            |
| File path lookup by pattern                            | `Glob`                      | Fast glob matching (`**/*.ts`, `src/**/Handler.php`)                           |
| Exact string or regex in file contents                 | `Grep`                      | Regex search across files, filterable by extension                             |
| AST structural pattern matching                        | `ast-grep`                  | Matches code by AST structure, not text                                        |
| Cross-file relationships, architecture                 | `devbot:graphify` (CLI+MCP) | Knowledge graph with communities, god nodes, paths                             |
| Full directory context for audit/analysis              | `repomix` (CLI)             | Packs files into single structured dump                                        |
| Markdown notes/docs in the memory vault                | `search-memories`           | Searches the project + global vault under the configured engine (qmd or mdctx) |

## Detailed Guidance

### Codebase engine (`devbot:codebase-index`)

The project's active codebase engine, selected by `codebase_index_provider` —
meaning-based search, definition lookup, call-graph tracing, and similarity
search. The two engines (`codebase-index`, `codebase-memory`) are mutually
exclusive, so exactly one is wired.

**Use when:**

- "Where is authentication logic?"
- "Find function that validates user permissions"
- "How is event bus configured?"

**Engine specifics** — each engine's MCP tools and usage are documented in the
ACTIVE engine's own skill: `devbot:codebase-index` resolves to whichever engine
is wired, so load it for the current tool set. Representative tools: the
`codebase-index` engine provides `codebase_search`, `codebase_peek`,
`implementation_lookup`, `call_graph`, `find_similar`; `codebase-memory`
provides `search_graph`, `search_code`, `trace_path`, `get_code_snippet`,
`get_architecture`.

**Tips:**

- Describe behavior, not syntax: "function that sends welcome emails" not "sendWelcomeEmail"
- Narrow by `directory` or file type when you know the area
- Prefer a cheap metadata-only lookup first when you only need to know WHERE code is, then `Read` for content

### graphify (CLI + MCP)

Knowledge graph with cross-file relationships, community detection, and graph traversal.

**Use when:**

- "What calls this function?" (cross-file)
- "How does module A depend on module B?"
- Understanding architecture and dependencies
- Refactoring spanning multiple files
- Searching mixed content (code + docs + PDFs + recordings)

**CLI tools:**

- `graphify query "<question>"` — BFS/DFS traversal from concept
- `graphify explain "<node>"` — full details for specific node
- `graphify path "<src>" "<dst>"` — shortest path between two concepts
- `graphify-report` (custom tool) — god nodes, communities, graph stats (removed; use MCP tools instead)

**MCP tools** (for structured graph introspection):

- `graphify_get_node` — full details for specific node
- `graphify_get_neighbors` — direct connections of node
- `graphify_get_community` — all nodes in community cluster
- `graphify_god_nodes` — most-connected nodes (core abstractions)
- `graphify_graph_stats` — summary statistics
- `graphify_shortest_path` — path between two concepts

**Tips:**

- Use `graphify query` (BFS default) for broad context ("what connects to X?")
- Use `graphify query --dfs` to trace specific dependency chain
- Run `graphify_god_nodes` MCP tool first when exploring unfamiliar architecture (god nodes, stats)
- Use `--budget N` to cap output at N tokens
- For structured queries (neighbors, community membership), use MCP tools

### repomix (CLI)

Packs directory contents into single structured file for full-context analysis.

**Use when:**

- Full audit of module or directory
- Generating complete architecture documents
- Packing all (or selected) files with directory structure
- Reading 5+ files from same area (more efficient than individual reads)
- Need complete module context for review or refactoring plan

**Tools:**

- `repomix pack <dir>` — pack local directory (outputs XML/MD/JSON/plain)
- `repomix pack --remote <url>` — pack GitHub repo
- `repomix pack --include "src/Auth/**"` — filter by patterns
- `repomix pack --compress` — Tree-sitter compression (~70% token savings)

**Tips:**

- Use `--include` to focus on relevant files (`"src/Auth/**"`)
- Use `--compress` for large repos (Tree-sitter compression, ~70% token savings)
- Never use both repomix AND the codebase engine for the same files — wastes tokens
- Output to file: `repomix pack <dir> --output output.xml` then read with `Read`

### Glob

Fast file path matching by pattern.

**Use when:**

- Finding files by name or extension
- Listing all files in directory matching pattern
- "Find all migration files", "list all test files for auth"

**Tips:**

- Use `**/*.php` for recursive, `*.php` for current directory only
- Results sorted by modification time (newest first)
- **Gitignored paths not surfaced** by `Glob` (or by `find` from repo root in shell pipelines respecting `.gitignore`). Files under `storage/`, `vendor/`, and other gitignored areas return zero matches even when they exist. To search gitignored areas, use `Read` with known canonical path, or `bash` with explicit absolute path (`ls /abs/path` or `find /abs/path -type f`), or `rg --no-ignore` for content search. See [[gotchas]] entry "Glob and find miss gitignored paths".

### Grep

Regex content search across files.

**Use when:**

- Searching for exact strings or regex patterns
- Finding all usages of specific class/function name
- Filtering by file extension with `include` parameter

**Tips:**

- Supports full regex: `"function\\s+\\w+"`, `"log.*Error"`
- Use `include` to narrow: `"*.php"`, `"*.{ts,tsx}"`
- Returns file paths + line numbers, sorted by modification time

### Memory-vault search (`search-memories`)

The canonical way to search the agent memory vault — `.md` notes under
`.agents/memory/` (latent notes, ADRs, PDRs, gotchas, patterns, work artefacts,
decisions, retrospectives). `search-memories` searches the CURRENT project
vault **and** the shared global store, under whichever engine
`memory_search_provider` selects (qmd or mdctx).

**Use when:**

- Recalling past lessons, decisions, or context from the vault
- Concept/keyword search across notes ("how did we decide X?", "what's the auth pattern?")
- Reading full matched notes — `search-memories` returns whole file bodies with frontmatter stripped

**Tools:**

- `search-memories <query>` — devbot-tools MCP tool or CLI; the route for vault search
- `reindex-memories` — refresh/rebuild the vault index after heavy edits (or when a search returns nothing)

**Engine specifics** — each engine's native CLI subcommands, MCP tools and
index locations are documented in the ACTIVE engine's own skill:
`devbot:qmd` when `memory_search_provider` is `qmd`, `devbot:mdctx` when it is
`mdctx`. Only the selected engine's skill is linked.

**Tips:**

- Prefer `search-memories` over `Glob`/`Grep` for ANY `.md` content search inside `.agents/memory/` — the search index is the canonical view of the vault, and `Glob`/`Grep` may miss gitignored vault paths
- Once a search returns file paths, `Read` the files directly when you need their exact content
- For non-vault markdown (e.g. project-root `README.md`, `docs/**/*.md`), `Glob`/`Grep`/`Read` are still right tools — vault search engines do not index those

### ast-grep

AST-based structural pattern matching.

**Use when:**

- Matching code structure regardless of formatting or variable names
- Finding all functions with specific signature pattern
- Structural refactoring queries

**Tips:**

- Pattern must be valid AST structure for language
- Auto-detects language from file extensions
- Use `lang` parameter to force language when ambiguous

## Decision Flowchart

1. **Searching `.md` content under `.agents/memory/`?** → `search-memories`
2. **Know exact file path?** → `Read`
3. **Know file name pattern?** → `Glob`
4. **Know exact string to find?** → `Grep`
5. **Need structural code pattern?** → `ast-grep`
6. **Need to find code by meaning?** → the codebase engine (`devbot:codebase-index` skill)
7. **Need to find definition?** → the codebase engine (`devbot:codebase-index` skill)
8. **Need callers/callees?** → the codebase engine (`devbot:codebase-index` skill)
9. **Need cross-file architecture?** → `graphify query` / MCP tools (`graphify_god_nodes`, `graphify_graph_stats`)
10. **Need full directory context?** → `repomix pack`
