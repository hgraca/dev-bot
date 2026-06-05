---
tags: [adr, search, qmd]
description: Decision to use QMD for memory vault semantic search
---

# Use QMD for Memory Vault Search

## Status
Accepted

## Context
Need a semantic search system for the memory vault that supports both keyword and vector search.

## Decision
Use QMD (Qwik Markdown Database) as the search backend.

## Consequences
- Requires `qmd` CLI to be installed
- Support lexical, vector, and hybrid document queries
- Document embeddings stored locally in `.ai/devbot/storage/`
