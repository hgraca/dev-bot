---
date: 2026-08-20
keywords: ["laravel", "singleton", "config", "test", "container"]
trigger-on: ["laravel-singleton-resolved-at-boot-config-test"]
---

## Config::set() does not affect a singleton already resolved at boot

Laravel singletons are cached once resolved; if a service provider resolves one during app boot (e.g. bus providers resolving a TelemetryCollector while building middleware), a later `Config::set()` in a test has no effect — `app(X::class)` returns the boot-time instance. Call `$this->app->forgetInstance(X::class)` after setting config so the next resolution re-runs the closure with the new config. The failure mode is silent: tests pass against the boot-time defaults and the new config appears ignored.
