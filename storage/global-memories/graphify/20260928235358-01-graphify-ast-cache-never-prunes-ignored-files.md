---
date: 2026-09-28
keywords: ["graphify", "ast-cache", "graphifyignore"]
trigger-on: ["graphify-cache-bloat", "graphifyignore-staleness"]
---

## Graphify's AST cache never prunes ignored files, so it diverges from graph.json

`graphify-out/cache/ast/` is a write-only parse cache: it stores a parsed-AST blob for every file graphify has ever indexed and never evicts entries when a file is later added to `.graphifyignore` or deleted. The graph itself (`graph.json`) is rebuilt respecting current ignore rules, so a repo can have `vendor/` correctly ignored while `cache/ast/` still holds stale entries for those ignored files — the cache bloats to gigabytes and its file count exceeds the ignore-respecting source set (on a large PHP monorepo: 83k files / 2.8 GB cache vs ~62k real source files). Fix: after tightening `.graphifyignore`, delete `graphify-out/cache/` entirely — it is regenerable and rebuilt lean on the next `graphify update`. Do not infer cache correctness from a correct-looking `.graphifyignore`.
