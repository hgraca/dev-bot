---
layout: page
title: Codebase Index
description: Semantic code search via Ollama embeddings.
nav_section: docs
---

Find code by describing what it does, not by guessing function names.

## What it does

- **Semantic search**: find functions, classes, and patterns by natural language
- **Call graph analysis**: trace callers and callees, find dependency paths
- **Community detection**: discover natural module boundaries
- **Incremental indexing**: only changed files are re-embedded after the first build

## How agents use it

Instead of grepping for keywords, agents describe what they're looking for in plain English and get back the relevant code locations.

## Local model

Powered by Ollama running `nomic-embed-text` for embeddings. Runs entirely on your machine.

**macOS platform note:** Ollama runs inside Docker Desktop on macOS, and Docker Desktop
does not pass the host Metal GPU through to Linux containers — so `nomic-embed-text`
embeddings run CPU-only on macOS hosts. This is a platform limitation, not a
misconfiguration (`size_vram: 0` is expected). For GPU-accelerated embeddings on macOS,
use an engine that runs natively on the host (e.g. qmd's Metal-backed models).

## See also

- [Graphify](/tools/graphify) — structural knowledge graph
- [QMD](/tools/qmd) — knowledge vault search
