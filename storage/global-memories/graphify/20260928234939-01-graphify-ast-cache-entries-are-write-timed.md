---
date: 2026-09-28
keywords: ["graphify", "cache", "mtime", "prune"]
trigger-on: ["graphify-cache-prune", "graphify-cache-mtime"]
---

## Graphify AST cache entries are write-timed, not read-timed

Graphify caches AST extraction under `graphify-out/cache/ast/<sha256>.json` (keyed by content hash) plus a `graphify-out/cache/stat-index.json` fastpath; mtime is stamped when an entry is written and is never refreshed by a cache hit, so an age-based prune (`find … -mtime +N -delete`) evicts entries for sources that are merely old-but-unchanged — valid entries, recomputed on the next `graphify update`. Because `stat-index.json` lets unchanged files skip re-extraction, a missing AST entry is often cheap to rebuild, and the CLI already ships `clear_cache()` (wipes `ast/`, `semantic/` and legacy flat entries). The cache directory is recreated on demand, so deleting files — or the directory itself — is safe; but never infer "last used" from mtime, and never read a stale mtime as proof the entry is unused.
