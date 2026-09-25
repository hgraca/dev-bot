---
date: 2026-09-24
keywords: ["laravel", "container", "giveConfig", "typeerror", "dependency-injection"]
trigger-on: ["laravel-container-config-injection", "giveConfig-null-param"]
---

## `giveConfig` into a non-nullable scalar constructor param throws TypeError when the config key is unset

When a service provider binds with `$this->app->when(Foo::class)->needs('$bar')->giveConfig('some.key')` and `some.key` resolves to `null` (typically `env('X')` with no default and nothing set), the container passes `null` into the constructor. If that parameter is typed `string`/`int` (non-nullable), PHP throws an uncaught `TypeError: Argument #1 ($bar) must be of type string, null given`. The failure surfaces as a generic 500 the first time the service is resolved from the container, and if the exception handler maps unhandled throwables to CRITICAL it logs every affected request as critical — so it looks like a runtime or connection failure while actually being pure DI misconfiguration. Fix: do not rely on the container to enforce a config default — either give the config an explicit default (`env('X', '')`) or resolve the binding through a closure that validates the config first and throws a domain-specific, descriptive exception (a clear "not configured" error beats a raw `TypeError`). A production-gated factory closure is a common shape: null adapter outside production, loud descriptive exception inside it.
