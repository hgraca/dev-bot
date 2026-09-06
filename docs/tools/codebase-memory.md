---
layout: page
title: Codebase Memory
description: Fast structural code intelligence via a persistent tree-sitter knowledge graph — no Ollama, no API key.
nav_section: docs
---

Find code by structure and meaning — call graphs, architecture, impact — backed by a persistent knowledge graph built from a native tree-sitter engine.

## What it does

- **Knowledge graph indexing**: functions, classes, call chains, HTTP routes, and cross-service links parsed from 160+ languages
- **Call graph tracing**: who calls a function and what it calls (`trace_path`)
- **Architecture overview**: languages, packages, routes, hotspots, clusters in one call (`get_architecture`)
- **Semantic + structural search**: bundled nomic embeddings, BM25, and regex structural queries (`search_graph`, `search_code`)
- **Impact analysis**: git diff → affected symbols with risk classification (`detect_changes`)
- **Cypher-like queries**: read-only relationship queries (`query_graph`)

## How agents use it

Instead of grepping for keywords or reading files one at a time, agents query the graph: trace callers of a function, map what a change touches, or get a whole-codebase architecture summary in a single structured call.

## Engine

Powered by `codebase-memory-mcp` (DeusData) — a single native binary with embeddings compiled in. No Ollama, no Docker, no GPU, no API key. Index persists under `~/.cache/codebase-memory-mcp/`.

## Selecting the engine

This module is one of two interchangeable codebase engines. Which one is active is set by `codebase_index_provider` in `.devbot.global.jsonc` (see [Configuration](/configuration)):

| Provider          | Engine                                                  |
| ----------------- | ------------------------------------------------------- |
| `codebase-index`  | Ollama-based semantic index (`opencode-codebase-index`) |
| `codebase-memory` | Tree-sitter knowledge graph (`codebase-memory-mcp`)     |

The two are mutually exclusive — flip the key, run `devbot reinit`, and only the selected engine is wired.

## See also

- [Codebase Index](/tools/codebase-index) — the sibling Ollama-based engine
- [Graphify](/tools/graphify) — structural knowledge graph
- [QMD](/tools/qmd) — knowledge vault search
- [Configuration](/configuration) — `codebase_index_provider` key
