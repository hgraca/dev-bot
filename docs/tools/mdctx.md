---
layout: page
title: mdctx
description: Zero-ML-dependency keyword search over markdown knowledge bases — RAKE keyword extraction + BM25 over a flat, git-diffable index. No embeddings, no GPU.
nav_section: docs
---

Find relevant markdown files in milliseconds — keyword search over the agent
memory vault (and any markdown corpus), backed by a flat JSON index you can
read, diff, and commit. No SQLite, no vector DB, no embedding model, no GPU.

## What it does

- **Keyword indexing**: RAKE-style keyword extraction (title/frontmatter +
  headings + emphasis boosted), auto-sized per file
- **BM25 ranking**: deterministic, fully offline, zero cost per index update
- **Git-diffable index**: one flat `context-index.json`; repeat builds are
  byte-stable (hash-cached, incremental)
- **Cross-model**: ships as a CLI (`mdctx`) and an MCP server (`mdctx-mcp`)
  exposing `search_context` / `refresh_index` / `list_context`

## How agents use it

The canonical memory-search route is **`search-memories`** — it scopes to the
current project vault + the shared global store and swaps engines
transparently. `mdctx`'s native CLI/index tools are for operators: build and
refresh the per-corpus indexes, browse an index, or search a corpus you built
yourself.

## Engine

Powered by the `mdctx` npm package (zachkepe/mdctx) — Node >= 18, deps only
zod/commander/MCP SDK. No models to pull, no VRAM pins, no Docker, no Ollama.
Installed by the mdctx module (`devbot install`) and registered as an MCP
server on `devbot init`.

Indexes are written to gitignored locations (mdctx does not follow symlinks,
so each real corpus gets its own index):

| Corpus                                   | Docs root                                 | Index file                                          |
| ---------------------------------------- | ----------------------------------------- | --------------------------------------------------- |
| Project vault (per project)              | `<project>/.agents/memory/latent`         | `<project>/.mdctx/context-index.json`               |
| Shared global store (one, under dev-bot) | `${DEV_BOT_ROOT}/storage/global-memories` | `${DEV_BOT_ROOT}/storage/.mdctx/context-index.json` |

## Selecting the engine

This module is one of two interchangeable memory-search engines. Which one is
active is set by `memory_search_provider` in `.devbot.global.jsonc` (see
[Configuration](/configuration)):

| Provider | Engine                                                          |
| -------- | --------------------------------------------------------------- |
| `mdctx`  | Zero-ML keyword BM25 over a flat git-diffable index (default)   |
| `qmd`    | Hybrid semantic + BM25 over per-project collections (llama/GPU) |

The two are mutually exclusive — flip the key, run `devbot reinit`, and only
the selected engine is wired. `mdctx` is keyword-only by design: no
semantic/vector search, no LLM reranking. Choose `qmd` when you need those.

## Known limits

- **Keyword-capped extraction**: per-file keywords are auto-sized (5–25);
  exact distinctive literals (error codes, slugs, hyphenated identifiers) may
  not be extracted as keywords and can return zero hits — fall back to
  `Grep`/`Glob` for literal-identifier lookups.
- **No symlink following**: each real corpus needs its own index (the shared
  store and each project vault are indexed separately).
- **MCP scope**: the opencode-registered mdctx MCP server roots at the shared
  global store, so its native tools browse global memories only — project
  vault search goes through `search-memories` (both stores).

## See also

- [QMD](/tools/qmd) — the sibling semantic/GPU engine
- [Configuration](/configuration) — `memory_search_provider` key
- [Codebase Memory](/tools/codebase-memory) — the sibling codebase engine swap
