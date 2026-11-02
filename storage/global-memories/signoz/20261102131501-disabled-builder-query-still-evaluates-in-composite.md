---
date: 2026-11-02
keywords: ["signoz", "composite-query", "disabled", "formula", "dashboard"]
aliases: ["disabled query still runs", "A/B formula with disabled inputs"]
---

## `disabled: true` on builder queries does not stop a formula from computing

A dashboard `CompositeQuery` whose `builder_query` inputs A and B both carry `disabled: true` still evaluates its `builder_formula` server-side — posting the stored panel payload returns real values. The flag governs the editor's visibility, not execution, so a flat-zero panel is never explained by it and "fixing" the flag changes nothing. Diagnose the panel by running its stored queries through the query API with the same variables; only then look at the data behind the formula.
