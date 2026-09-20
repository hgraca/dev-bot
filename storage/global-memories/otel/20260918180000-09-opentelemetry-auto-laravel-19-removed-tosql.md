---
date: 2026-09-18
keywords: ["otel", "opentelemetry", "mongodb", "laravel", "composer-patches"]
trigger-on: ["opentelemetry-auto-laravel", "mongodb-tosql", "composer-patches"]
---

## The MongoDB toSql() patch for opentelemetry-auto-laravel is obsolete from 1.9.x

`open-telemetry/opentelemetry-auto-laravel`'s Eloquent hook used to set `db.statement` through `$builder->getQuery()->toSql()`, which throws `BadMethodCallException` on MongoDB connections — hence the `cweagans/composer-patches` patch (falling back to `toMql()`) that sibling projects still carry. Version 1.9.1 removed that call entirely; the hook now sets only `laravel.eloquent.*` attributes, so on 1.9.1 and later there is nothing to patch and the patch would fail to apply. Check the installed hook source for `toSql` before porting it. A side effect is that `db.statement` stays empty on Eloquent spans, so dashboards must key on the span name instead.
