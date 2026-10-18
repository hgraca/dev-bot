---
title: "QMD"
description: "BM25 keyword search over the knowledge vault."
skills: ["qmd"]
tools: ["qmd"]
---

QMD (Query Markdown Documents) powers the knowledge vault — decisions, patterns,
and gotchas are searchable by keyword.

QMD is one of two interchangeable memory-search engines; it is active only when
`memory_search_provider` is `"qmd"` in `.devbot.global.jsonc` (default is
`mdctx`, see [mdctx](/modules/agentic/mdctx) and
[Configuration](/configuration)). Agents search the vault through
**`search-memories`**, which swaps engines transparently.

## What it does

- **BM25 keyword search**: deterministic, offline ranking over registered
  collections — no model download, no embeddings, no GPU (ADR
  `20260913072905-qmd-bm25-only-no-model-downloads`)
- **Collections**: the project memory tree, the shared global store, and any
  custom collection configured under `memory_collections`
- **Keyword-first**: exact terms and identifiers are the strong case

## How agents use it

Agents search the vault to recall past decisions, known gotchas, and established
patterns before acting — preventing repeated mistakes.

## Configuration

No project configuration is required for the built-in project and global
collections. Add a custom corpus under `memory_collections` (project or global
config) and it is registered as `dev-bot-custom-<path-hash>` during reindex
(the logical key is the `--collection` selector; two keys naming the same path
share one registration). The
per-collection `semantic` flag is reserved: `true` is accepted and stored, but
qmd runs the BM25 path and a search emits a `NOTICE`.

## See also

- [Memory Management](/module-reference) — vault structure and conventions
- [mdctx](/modules/agentic/mdctx) — the sibling keyword engine
- [Graphify](/modules/agentic/graphify) — structural knowledge graph
- [Configuration](/configuration) — `memory_search_provider` and
  `memory_collections`
