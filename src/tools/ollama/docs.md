---
title: "Ollama"
description: "Local LLM inference server."
---

Ollama runs as a Docker container on port 18434, powering embeddings for semantic code search and local model inference.

## What it provides

- **Embeddings**: `nomic-embed-text` model for Codebase Index
- **Local inference**: optional local LLM for any task
- **Healthcheck**: Docker healthcheck ensures service readiness
- **Persistent storage**: models stored in `storage/ollama`

## How agents use it

Codebase Index uses Ollama for semantic code search embeddings. Other tools can use it for local inference without cloud API calls.

## Management

```bash
devbot up     # start the container
devbot down   # stop the container
```

## Configuration

No project configuration is required.

## See also

- [Codebase Index](/modules/agentic/codebase-index) — semantic code search
