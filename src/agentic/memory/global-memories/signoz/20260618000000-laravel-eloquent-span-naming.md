---
date: 2026-06-18
keywords: ["signoz", "laravel", "otel", "traces", "eloquent"]
---

## Laravel Eloquent OTel spans named by model class, not sql

Laravel's OpenTelemetry auto-instrumentation for Eloquent models names spans as `App\Models\X::method` (e.g. `App\Models\Booking::find`), not containing "sql". The standard OTel `db.system`, `db.operation`, `db.statement` attributes are empty for these spans. SigNoz dashboards filtering DB queries by `name CONTAINS 'sql'` will never match. Instead filter by `name CONTAINS 'Models'` (Laravel convention) or filter by `db.system = 'mysql'` if/when the Laravel OTel instrumentation is updated to populate that attribute.
