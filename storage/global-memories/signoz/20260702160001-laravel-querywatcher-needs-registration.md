---
date: 2026-07-02
keywords: ["signoz", "otel", "laravel", "pdo", "query-watcher"]
trigger-on: ["signoz-sql-tracing", "signoz-db.query.text", "opentelemetry-auto-pdo"]
superseded_by: ["laravel/20260930091000-01-laravel-querywatcher-leaks-connector-driver-alias.md"]
---

## `opentelemetry-auto-laravel` QueryWatcher exists but is NOT auto-registered — use `opentelemetry-auto-pdo` instead

> **SUPERSEDED 2026-09-30** — the conclusion below is wrong. The package does register QueryWatcher, from a Hook: `Hooks/Illuminate/Foundation/Application.php` calls `registerWatchers($application, new QueryWatcher(...))`, so its `sql <OP>` spans and DB attributes appear with no app-side registration. See `laravel/20260930091000-01-laravel-querywatcher-leaks-connector-driver-alias.md`.

The `open-telemetry/opentelemetry-auto-laravel` package (v1.7.0) includes `Watchers/QueryWatcher.php` that sets `db.query.text` and other DB attributes on Eloquent query spans. However, the package's `_register.php` only calls `LaravelInstrumentation::register()` which registers `Hooks` — it never instantiates or registers `Watchers`. The QueryWatcher code exists in vendor but `db.query.text` is never populated unless a custom service provider calls `(new QueryWatcher(...))->register($app)`. The simpler approach is adding `open-telemetry/opentelemetry-auto-pdo` to composer.json, which auto-activates via the C extension without any app code changes. This populates `db.statement` and `db.query.text` on all PDO calls across the application.
