---
date: 2026-08-07
keywords: ["laravel", "eloquent", "factory", "phpunit", "refresh-database"]
trigger-on: ["eloquent-factory-eager-query", "refresh-database-failure", "factory-definition-db-call"]
---

## Factory definition() DB queries break RefreshDatabase when called eagerly

Calling `Model::all()` or any DB query directly in a factory's `definition()` method evaluates at class-load time, before `RefreshDatabase` sets up the test database. This causes a connection error. Fix: wrap in `fn () =>` closure so the query executes lazily at model-creation time, after the test DB is migrated. Example: `'benefits' => fn () => Benefit::all()->map(...)->toArray()` instead of `'benefits' => Benefit::all()->map(...)->toArray()`.
