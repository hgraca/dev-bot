---
date: 2026-08-20
keywords: ["laravel", "container", "contextual-binding", "DI", "dead-code"]
trigger-on: ["laravel-contextual-binding-dead"]
---

## Contextual DI bindings become silent dead code when a constructor param is removed

Laravel's `$app->when(X::class)->needs('$param')->give(...)` contextual bindings are never validated against the target constructor. When a class drops a constructor parameter (e.g. `SentryCollector` moved its `$cache` dependency into `RedisAlertSuppressionGuard`), the matching `when()->needs('$cache')` block stays wired with no error — Composer, PHPStan, and CS-fixer all pass. It silently misleads future readers into thinking the class still depends on that service.

When refactoring a constructor, always grep for and remove any `when(X::class)->needs('$...')` contextual bindings for the dropped parameter, plus the now-unused `use` import it referenced.
