---
name: devbot:mdctx
description: "Use this skill whenever the user asks to search notes, find documents, or look up information in markdown knowledge bases using mdctx — keyword (BM25) search over a flat, git-diffable index of notes, docs, and transcripts. Use it even if they do not say 'mdctx'."
---

# mdctx — Markdown Context Keyword Search

Zero-ML-dependency keyword index for markdown context files. `mdctx` indexes a
directory of `.md`/`.mdx` files once (RAKE keyword extraction + BM25 over
titles and keywords), then answers "which files are relevant to X" in
milliseconds from a single flat JSON file. No embeddings, no vector DB, no
GPU, no model downloads.

mdctx is one of the two **memory-search engines** dev-bot can use. It is active
only when `memory_search_provider` is `mdctx` (the default) in
`.devbot.global.jsonc`; the alternative engine is qmd (semantic + BM25 over
per-project collections). Whichever engine is selected, **memory search routes
through `search-memories`** (see `devbot:search-memory`) — this skill documents
mdctx's native surface for engine-specific work (building/refreshing indexes,
browsing the index), not the everyday search route.

## When to Use

| Situation                                                         | Tool                                                |
| ----------------------------------------------------------------- | --------------------------------------------------- |
| Building/refreshing an mdctx index for a markdown root            | `mdctx build`                                       |
| Keyword search against an mdctx index (files relevant to a query) | `mdctx search`                                      |
| Searching the memory vault via mdctx (engine-native)              | `mdctx search` + `Read`                             |
| Checking what the mdctx MCP server exposes                        | `search_context` / `refresh_index` / `list_context` |

**Prefer `search-memories` for memory-vault search.** It scopes to the current
project vault + the shared global store and swaps engines transparently. This
skill's CLI is for operators building/refreshing indexes and for engine-native
queries (e.g. a raw index you built yourself).

## How to Call

```bash
# Index every .md/.mdx file under a directory (incremental — only changed
# files are re-processed; hash-cached so repeat builds are byte-stable)
mdctx build <dir> [-o <index.json>] [-k <n>]

# Search the index (BM25 over each file's title + keywords)
mdctx search "<query>" [-i <index.json>] [-n <limit>] [--json]
```

### Key commands

| Command                                | Description                                                          | Example                                                          |
| -------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `mdctx build <dir> -o <index>`         | Build/refresh a keyword index for a markdown root                    | `mdctx build .agents/memory/latent -o .mdctx/context-index.json` |
| `mdctx search "<q>" -i <index> --json` | Ranked files relevant to the query (JSON)                            | `mdctx search "auth flow" --json -n 5`                           |
| `mdctx-mcp` (MCP server)               | Native MCP tools `search_context` / `refresh_index` / `list_context` | env `MDCTX_ROOT` + `MDCTX_INDEX`                                 |

### Index locations (dev-bot conventions)

`mdctx` does **not** follow symlinks, so each real root gets its own index:

| Corpus                                   | Docs root                                 | Index file                                          |
| ---------------------------------------- | ----------------------------------------- | --------------------------------------------------- |
| Project vault (per project)              | `<project>/<devbot-dir>/memory/latent`    | `<project>/.mdctx/context-index.json`               |
| Shared global store (one, under dev-bot) | `${DEV_BOT_ROOT}/storage/global-memories` | `${DEV_BOT_ROOT}/storage/.mdctx/context-index.json` |

The project index is built by the mdctx module's `init.sh` on `devbot reinit`;
the global index by the memory module's `init.sh`. `search-memories` searches
both. `reindex-memories` refreshes them.

### Search result shape

`mdctx search --json` returns:

```json
[{ "path": "sub/note.md", "title": "Note Title", "score": 1.3, "matchedKeywords": ["auth", "flow"] }]
```

`path` is **relative to the indexed root** — resolve it against the root to
`Read` the file (mdctx has no `get`; the body is a plain file read).

## Semantics & limits

- **Keyword-only**: mdctx matches on RAKE-extracted keywords from each file's
  title/frontmatter/headings + body emphasis, ranked with BM25. There is no
  semantic/vector search, no LLM reranking, no fuzzy paraphrase matching —
  choose qmd (`memory_search_provider: "qmd"`) if you need those.
- **Deterministic + offline**: no model, no GPU, no cost per index update; the
  index JSON is git-diffable.
- **No symlink following**: a docs tree reached only via symlinks is never
  indexed — register the real path.

## Setup

Installed by the mdctx module (`devbot install`): global npm package `mdctx`
(Node >= 18). MCP registration happens on `devbot init/reinit`.

**Claude Code harness divergence:** the claudecode MCP manifest sets no
`MDCTX_ROOT`/`MDCTX_INDEX` (that harness performs no placeholder substitution),
so under Claude Code the `mdctx-mcp` server roots at the opened project's cwd
and auto-heals by writing `context-index.json` into that project root — i.e.
whole-project keyword search, not the shared-store convention above. This
harness is not used in the dev-bot workspace; if you enable it, set
`MDCTX_ROOT`/`MDCTX_INDEX` explicitly in `.mcp.json` for the intended corpus.

**Never run `mdctx init`** — it installs git hooks + a GitHub Actions workflow
into the project. dev-bot owns index lifecycle through its own
`init.sh`/`reindex-memories`; the engine's auto-config commands are not used
(same policy as the other engines).
