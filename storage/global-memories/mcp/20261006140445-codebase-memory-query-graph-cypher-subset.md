---
date: 2026-10-06
keywords: ["mcp", "codebase-memory", "query_graph"]
trigger-on: ["codebase-memory-query-graph"]
---

## codebase-memory `query_graph`: no `type()`/`UNION`; `WRITES` is not DB writes

The codebase-memory gateway's read-only Cypher subset (`query_graph`) supports neither `type(r)`
(fails: "unsupported function 'type'") nor `UNION` (parse error). Match a specific edge kind by label
instead — `MATCH (f)-[:HTTP_CALLS]->(t) …` — and map the kind in code; `WHERE f.qualified_name IN [...]`
works for batching several sources in one query. The `WRITES` edge targets **variables/fields**
(`raw`, `options`, `key`), not a datastore — do not map it to a DB sink. Reliable structural signals:
`HTTP_CALLS` (external api), `ASYNC_CALLS` (queue), `EMITS` (event); nodes carry `is_entry_point`,
`is_test`, `file_path`, `qualified_name`. Note `detect_changes` is working-tree-oriented (returned 0
changed files for a committed change), and `is_entry_point` can be empty for a project that was indexed
without it — do not treat "no callers" as "entry point".
