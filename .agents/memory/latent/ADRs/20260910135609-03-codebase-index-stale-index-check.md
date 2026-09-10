---
date: 2026-09-10
keywords: ["codebase-index", "reinit", "reindex", "devbot"]
---

## Stale codebase-index schema is detected from the index DB and reindexed in the background

`src/agentic/codebase-index/init.sh` (run per project by `devbot reinit` and `devbot update`'s `reinit --all`) calls `_codebase_index_reindex_if_stale` for each enabled harness with an existing `.opencode/index`/`.claude/index`. The package has no cheap freshness command — its own check hashes every project file before comparing schema versions, which made reinit hang — so the helper reads the index DB's stored schema versions for the current branch catalog (newest `file-hashes.<id>.json`) via `python3`'s sqlite3 module and compares them to the constants grepped from the installed package (`CALL_GRAPH_RESOLUTION_VERSION`, `SWIFT_PARSER_VERSION`, `METAL_PARSER_VERSION`, `SYMBOL_EXTRACTOR_VERSION`). When current it prints "up to date"; when stale (or undeterminable) it launches `cbi index` detached (`nohup … &`, log at `.agents/logs/codebase-index-reindex.log`) and prints "out of date … reindexing in the background as of <ts>". It never blocks and never fails init. Known limitation (accepted): the current branch's catalog is approximated by the newest `file-hashes` file, so a branch switch without a session since can miss a stale current-branch catalog; a robust fix needs the package to expose its current catalog id.
