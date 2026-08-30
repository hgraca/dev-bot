---
layout: page
title: QMD
description: Semantic search over the knowledge vault.
nav_section: docs
---

QMD (Query Markdown Documents) powers the knowledge vault — all your decisions, patterns, and gotchas are searchable by meaning.

## What it does

- **Hybrid search**: combines BM25 (keyword) + vector (semantic) + LLM reranking
- **Collections**: organize knowledge by project or topic
- **Embeddings**: auto-embeds markdown files for semantic retrieval

## How agents use it

Agents search the vault to recall past decisions, known gotchas, and established patterns before acting — preventing repeated mistakes.

## Local model

Uses GGUF models (`embeddinggemma`, `qwen3-reranker`, `qmd-query-expansion`) self-managed by QMD.

## See also

- [Memory Management](/module-reference) — vault structure and conventions
- [Graphify](/tools/graphify) — structural knowledge graph
