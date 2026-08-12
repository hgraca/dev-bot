---
layout: page
title: Graphify
description: Structural knowledge graph auto-built from your codebase.
nav_section: docs
---

Graphify builds a persistent knowledge graph from your codebase — queries run against AST data, no API calls needed.

## What it does

- **Auto-builds** a graph on every commit (or every 30 minutes)
- **God nodes** identify the most connected symbols in the codebase
- **Community detection** discovers natural module boundaries
- **Cross-file relationships** trace dependencies and call graphs
- **Query tools**: `graphify query`, `graphify path`, `graphify explain`

## How agents use it

Agents query graphify to understand code structure — trace how a function connects to others, find all callers of a method, or discover which modules would be affected by a change.

## Local model

Uses Ollama embeddings for semantic understanding. No cloud API calls.

## See also

- [Codebase Index](/tools/codebase-index) — semantic code search
- [QMD](/tools/qmd) — knowledge vault search
