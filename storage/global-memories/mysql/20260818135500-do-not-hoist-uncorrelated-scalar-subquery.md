---
date: 2026-08-18
keywords: ["mysql", "scalar-subquery", "uncorrelated", "race-condition", "count"]
trigger-on: ["scalar-subquery-hoisting", "correlated-subquery"]
---

## Don't hoist an uncorrelated scalar subquery out of the SELECT — it's already evaluated once

A scalar subquery like `(SELECT COUNT(1) FROM t WHERE account_id = ?)` with only bound parameters (no reference to the outer row's columns) is **uncorrelated**, so MySQL evaluates it once per statement, not per row. Hoisting it into a separate `$count = ...->count()` query before the main `SELECT` is a pessimization with a correctness cost: an insert/delete between the two statements makes the count come from a different dataset than the rows it offsets, creating duplicate or misordered priorities. Keep the subquery inline to get one consistent statement. Only hoist when the subquery is genuinely correlated (references the outer table). This bit `CancellationEngine\PolicyRepository::getPolicies()`, where a backlog mislabeled the constant subquery as "correlated per-row".
