---
date: 2026-09-16
keywords: ["devbot", "codebase-memory", "atomic-write", "indexer", "race"]
trigger-on: ["devbot-codebase-memory-index", "devbot-non-atomic-write"]
---

## An in-place non-atomic rewrite of a tracked source file races the codebase-memory indexer and reports "Pipeline failed"

`codebase-memory` re-indexes on file changes, so a script that rewrites a tracked source file with a truncating write (`pathlib.Path.write_text(...)`) can be read **mid-write** — the indexer sees a half-written or empty file and fails with a generic `{"status":"error","hint":"Pipeline failed. Check repo_path exists and contains source files."}` that points nowhere near the real cause. Diagnosis: compare that run's timestamp against the file's mtime; a successful run minutes earlier plus a failure exactly at the write is the signature, and a clean re-index with nothing being written confirms it. Fix the habit, not the indexer — use the editor/edit tool, which writes atomically, rather than a scripted in-place rewrite; if a script must rewrite, write a temp file and `os.replace` it. Note the failure is logged into `.agents/logs/` (rotated to `.agents/logs/rotated/`), which the harness surfaces as an exit-time warning — so a transient tooling race shows up as a scary session-level alert.
