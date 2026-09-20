---
date: 2026-09-10
keywords: ["laravel", "factory", "afterMaking", "auto-increment", "phpunit"]
trigger-on: ["laravel-factory-explicit-id-collision", "database-transactions-auto-increment"]
---

## Laravel factory afterMaking runs after attribute expansion — explicit ids can be stolen by auto-increment rows

Laravel executes a factory's `afterMaking` callbacks only *after* `makeInstance()` expands the definition, and a `Factory` instance used as an attribute value (e.g. `'account_id' => Account::factory()`) is persisted with `create()` even when the parent is built via `make()`. Related rows therefore exist — and consume auto-increment ids — before any `afterMaking` code runs. Under `DatabaseTransactions` the rows roll back but the table's `AUTO_INCREMENT` counter does not, so a test that pins an explicit id (a fixture-derived id, or `->withCustomerId(578)`) can find that id already taken by an expansion-created row; an existence guard like `if (!Model::where('id', $id)->exists())` then silently skips creating the intended record and downstream code reads the wrong row. Fix by reserving the explicit-id record *before* the factory chain runs (create it up front in the test), not in `afterMaking`/`afterCreating`. Reproduce deterministically with `ALTER TABLE <table> AUTO_INCREMENT = <id>` before running the test.
