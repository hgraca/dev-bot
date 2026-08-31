---
date: 2026-08-22
keywords: ["qmd", "search-memories", "embed", "bm25"]
trigger-on: ["qmd-embed", "search-memories"]
---

## qmd embed is unnecessary for BM25 search; unscoped embed re-embeds the whole vault

`qmd embed` (without `-c <collection>`) generates vector embeddings for the _entire_ index — every registered collection — by calling the local Ollama embedding model once per document. It is slow and requires Ollama to be running. `qmd search` is BM25 keyword search and needs no embeddings at all. The dev-bot `search-memories` tool uses `qmd search`, so its tests must not call `qmd embed` — doing so re-embeds the whole memory vault on every run for no benefit (this made the e2e suite time out). Only scope with `qmd embed -c <name>` when a collection genuinely needs vector search.
