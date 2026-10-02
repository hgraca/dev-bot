---
date: 2026-10-02
keywords: ["graphify", "scope", "graphifyignore", "managed-block", "placeholder-graph"]
---

## Graphify index scope is enforced by a terminal managed block in .graphifyignore

The graphify module indexes only `src/` and/or `app/`, never the project root. Scope is
carried by a managed `SOURCE SCOPE (auto)` block in each project's `.graphifyignore`,
written by `_graphify_write_source_scope` on `devbot init`/`reinit` and re-applied on
`devbot up`, using bare negations (`/*`, `!src`, `!app`). The writer treats the block as
terminal — everything from the opening marker to EOF is managed — which lets it heal the
stale or truncated blocks the retired git-hook writer left behind and keeps re-runs
byte-idempotent. `graphify update <path>` cannot express scope (it moves the output dir),
so every build runs `update .`. When neither directory exists the block is `/*` (indexes
nothing) and the module should be disabled (`"graphify": false`). `init`/`up` also seed an
empty `graphify-out/graph.json` when missing so the MCP server can start before the first
build. Before this change `init.sh` only logged the detected scope while always running
`update .`, so this repo's graph had grown to 342k nodes dominated by vendor/storage/docs.
