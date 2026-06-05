---
date: 2026-07-31
keywords: ["phpunit", "mockery", "eloquent", "alias-mock"]
trigger-on: ["eloquent-model-static-calls", "mockery-alias-mock"]
---

## Mocking Eloquent static calls without a DB connection requires alias mocking

When writing unit tests for services that use Eloquent models via static calls (e.g. `Model::where()`, `Activity::create()`), the project's base `Tests\TestCase` cannot be used because it extends `DatabaseTransactions` and requires a live DB connection. Instead, extend `PHPUnit\Framework\TestCase` and use Mockery alias mocking (`Mockery::mock('alias:' . Model::class)`).

Do NOT use `makePartial()` on Eloquent models — it triggers the Eloquent boot sequence which calls `getConnectionResolver()->connection()` and fails with "Call to a member function connection() on null" when no Laravel container is available.

For `Model::create()`, the alias mock should return a new model instance to satisfy the finally-block code that might call it. For fluent query builder chains (`::where()->orderBy()->first()`), mock each link to return `$this` and the terminal method to return the expected value.
