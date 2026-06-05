---
date: 2026-04-17
keywords: ["graphify", "graph"]
---

## Graphify cache can be disproportionately large

Running Graphify on DevBot's own codebase produced a modest 22-node graph from 7 files, but the cache directory (`graphify-out/cache/`) accumulated 62,410+ JSON files. Graphify's value is for real application codebases, not infrastructure scripts. Be aware of disk usage.
