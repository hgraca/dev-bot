---
date: 2026-08-06
keywords: ["opencode", "codebase-index", "EISDIR"]
---

## Stale opencode-codebase-index cache causes EISDIR on indexing.lock

The opencode-codebase-index plugin caches in `~/.cache/opencode/packages/opencode-codebase-index@latest/`. Version 0.9.0 has a race condition where the file-change watcher and git branch-change watcher concurrently call `index()` → `acquireIndexingLock()`, corrupting `.opencode/index/indexing.lock` into a directory. The recovery path (`recoverFromInterruptedIndexing`) uses `unlinkSync` which fails on directories, so the corruption persists. Error appears in OpenCode TUI as: `EISDIR: illegal operation on a directory, open '.../.opencode/index/indexing.lock'`. Fix: remove stale cache (`rm -rf ~/.cache/opencode/packages/opencode-codebase-index@latest ~/.cache/opencode/packages/opencode-codebase-index`), reinstall plugin (`opencode plugin opencode-codebase-index --force`), then rebuild index with `force=true`. Verify with `ls .opencode/index/` — no `indexing.lock` file or directory should exist.
