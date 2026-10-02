---
date: 2026-09-30
keywords: ["laravel", "opentelemetry", "querywatcher", "db.system.name", "semconv"]
trigger-on: ["laravel-otel-db-attributes", "laravel-custom-db-connector"]
---

## `opentelemetry-auto-laravel`'s QueryWatcher leaks the connection's driver name straight into `db.system.name`

`QueryWatcher::getDbSystemName()` maps the known Laravel drivers (`mysql`, `pgsql`, `mariadb`, `sqlsrv`) to their semconv values, but falls back to `default => $driverName` and returns the raw driver string unchanged. An app that registers a **custom** DB connector — e.g. `config/database.php` declaring `'driver' => 'gete'` — therefore stamps `db.system.name = "gete"` on every Eloquent query span: 714k of 3.0M spans (~24%) in one production service. That surfaces as a bogus "gete" DB system in SigNoz and breaks any grouping on the key. The PDO-level spans on the same connections are unaffected, because `PDOTracker::mapDriverNameToAttribute()` reads `PDO::ATTR_DRIVER_NAME` (the real driver) and returns `other_sql` for anything it does not recognise instead of passing the value through. Fix app-side by giving the connector a real driver name, or normalise the alias in the collector. This also corrects the older belief that QueryWatcher is never instantiated: the package registers it from a Hook — `Hooks/Illuminate/Foundation/Application.php` calls `registerWatchers($application, new QueryWatcher(...))` — so its `sql <OP>` spans and DB attributes do appear without any app-side registration.
