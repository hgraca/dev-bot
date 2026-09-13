---
date: 2026-09-13
keywords: ["qmd", "bm25", "embeddings", "memory", "memory_search_provider"]
see: ["ADRs/20260907140000-mdctx-memory-search-engine-swap.md"]
---

## qmd is BM25-only behind the memory module — no model downloads, no embeddings

The `qmd` module is a private implementation detail of the `memory` module: agents never invoke qmd directly, they call the `search-memories` tool, which for the qmd engine runs `qmd search` — the BM25-only path (`search_qmd` in `src/agentic/memory/tools/search-memories/search-memories.py`). No consumer issues a semantic query (`qmd query`) or an embed against the passive memory vault. The entire semantic stack is therefore dead weight: qmd's own llama.cpp GGUF models (`embeddinggemma-300m`, `qmd-query-expansion-1.7b`, `qwen3-reranker-0.6b` — ~2 GB), the `qmd pull` download in `qmd/install.sh`, the `qmd embed` steps in `qmd/init.sh`, `qmd/update.sh`, `memory/tools/reindex-passive-memories.sh` and `memory/tools/reindex-memories/reindex-memories.mcp.sh`, plus `qmd/tools/share-with-ollama.sh` (which imports those GGUFs into the ollama container), all exist only to compute vectors and reranks nothing reads. They also cost real resources: a first-install multi-GB download, llama/GPU (or all-core CPU) work on every reindex, VRAM contention, and a cross-process llama lock to serialize it.

We adopt **BM25-only qmd**: the module is used exclusively through `search-memories`, and only its keyword path. The lifecycle must neither download models nor embed — `install.sh` no longer runs `qmd pull`; the index lifecycle reduces to `qmd cleanup && qmd update` (the command prune mode already uses), which maintains the index the BM25 `search` reads without loading a model; `qmd embed`, the llama serialization lock in `init.sh`, and the qmd→ollama model share (`up.sh`, `tools/share-with-ollama.sh`, the qmd-cache mount in `src/tools/ollama/docker-compose.yml`) are removed. The `QMD_LLAMA_GPU`, `QMD_EXPAND_CONTEXT_SIZE` and `QMD_RERANK_CONTEXT_SIZE` env vars are semantic-path leftovers.

Removing the lifecycle code alone does not prevent an agent from triggering a download or a semantic query: the `qmd` MCP server and `devbot:qmd` skill still expose `query` (auto-expand + rerank) and `embed` directly. Closing that surface — restricting or removing direct qmd access so the semantic path is unreachable — is required follow-up for this decision to hold. `mdctx` (RAKE + BM25, zero-ML) already follows this principle and remains the default engine.
