---
name: search-code
description: "Code search tool selection guide. Use this skill whenever you need to find code, understand architecture, locate definitions, or explore the codebase — helps choose the right tool (grep vs semantic search vs call graph) for each search scenario."
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

| Question type                                          | Tool                    | Why                                                    |
| ------------------------------------------------------ | ----------------------- | ------------------------------------------------------ |
| Semantic search ("where is auth logic?")               | `codebase_search`       | Hybrid semantic + keyword, returns full code content   |
| Quick location lookup ("find payment handler")         | `codebase_peek`         | Same search, returns only metadata — saves ~90% tokens |
| Jump to definition ("where is validateToken defined?") | `implementation_lookup` | Finds authoritative source, skips tests/docs/examples  |
| Who calls this? / What does this call?                 | `call_graph`            | Traces callers or callees by function name             |
| Find similar code (duplicate detection, refactoring)   | `find_similar`          | Vector similarity on code snippet                      |
| File path lookup by pattern                            | `Glob`                  | Fast glob matching (`**/*.ts`, `src/**/Handler.php`)   |
| Exact string or regex in file contents                 | `Grep`                  | Regex search across files, filterable by extension     |
| AST structural pattern matching                        | `ast-grep`              | Matches code by AST structure, not text                |
| Cross-file relationships, architecture                 | `graphify` (CLI+MCP)    | Knowledge graph with communities, god nodes, paths     |
| Full directory context for audit/analysis              | `repomix` (CLI)         | Packs files into single structured dump                |
| Markdown notes/docs in memory vault                    | `qmd` (CLI)             | Hybrid lex+vec+rerank over indexed `.md` collections   |

## Detailed Guidance

### codebase-index (opencode-index)

Semantic + keyword hybrid search. Best general-purpose code finder.

**Use when:**

- "Where is authentication logic?"
- "Find function that validates user permissions"
- "How is event bus configured?"

**Tools:**

- `codebase_search` — full code content in results
- `codebase_peek` — metadata only (file, line, name, type) — prefer when you just need locations
- `implementation_lookup` — jump to where symbol defined (prefers real code over tests)
- `call_graph` — trace callers/callees of function
- `find_similar` — find code similar to given snippet

**Tips:**

- Describe behavior, not syntax: "function that sends welcome emails" not "sendWelcomeEmail"
- Filter by `chunkType` (function, class, method, interface) to narrow results
- Filter by `directory` or `fileType` when you know area
- Use `codebase_peek` first when you only need to know WHERE code is, then `Read` to get content

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
- Never use both repomix AND codebase-index for same files — wastes tokens
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

### qmd (CLI)

Hybrid markdown search over memory vault — combines BM25 keyword (`lex`), semantic vector (`vec`), and hypothetical-document (`hyde`) search with LLM reranking.

**Use when:**

- Searching `.md` content under `.agents/memory/` (latent notes, ADRs, PDRs, gotchas, patterns, work artefacts, decisions, retrospectives)
- Looking up past lessons, decisions, or context from vault
- Reading vault files by canonical path (`qmd get` works on gitignored `.ai/` paths where `Glob` does not)
- Concept search across notes ("how did we decide X?", "what's auth pattern?")

**Tools:**

- `qmd query "question"` — hybrid search with auto-expansion + reranking
- `qmd query $'lex: ...\nvec: ...'` — structured query document
- `qmd search "keywords"` — BM25 only (no LLM, faster)
- `qmd get <path>` — read single document by path
- `qmd multi-get <pattern>` — batch fetch by glob or comma-separated paths
- `qmd status` — list indexed collections and health

**Indexed collections:**

- `devbot` — entire memory vault (latent, work, reference, thinking, bootstrap)
- Root: `<project>/.ai/devbot/memory` (symlink into `storage/memory/projects/<project>/`)

**Tips:**

- For exact term/path lookup: `qmd search "PDRs gotcha"`
- For concept search: `qmd query "how did we decide X?"`
- For structured queries: `qmd query $'lex: PDRs\ngotcha\nvec: what patterns do we have for auth?'`
- Use `--json --explain` to see score traces: `qmd query --json --explain "question"`
- **Set env vars** when running qmd CLI directly: `XDG_CACHE_HOME="${DEVBOT_ROOT}/storage" QMD_LLAMA_GPU=true qmd query "..."` — redirects cache to DevBot storage and enables GPU acceleration
- Prefer `qmd` over `Glob`/`Grep` for ANY `.md` content search inside `.agents/memory/` — qmd's index is canonical view of vault, and `Glob`/`Grep` may miss gitignored vault paths
- For non-vault markdown (e.g. project-root `README.md`, `docs/**/*.md`), `Glob`/`Grep`/`Read` are still right tools — qmd does not index those

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

1. **Searching `.md` content under `.agents/memory/`?** → `qmd query` / `qmd get`
2. **Know exact file path?** → `Read`
3. **Know file name pattern?** → `Glob`
4. **Know exact string to find?** → `Grep`
5. **Need structural code pattern?** → `ast-grep`
6. **Need to find code by meaning?** → `codebase_search` / `codebase_peek`
7. **Need to find definition?** → `implementation_lookup`
8. **Need callers/callees?** → `call_graph`
9. **Need cross-file architecture?** → `graphify query` / MCP tools (`graphify_god_nodes`, `graphify_graph_stats`)
10. **Need full directory context?** → `repomix pack`
