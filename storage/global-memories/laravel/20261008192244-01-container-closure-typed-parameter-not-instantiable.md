---
date: 2026-10-08
keywords: ["laravel", "service-container", "contextual-binding"]
aliases: ["Target [Closure] is not instantiable", "give closure-typed parameter"]
trigger-on: ["laravel-service-container-contextual-binding"]
---

## A Closure-typed constructor parameter cannot be bound with needs()->give()

`$this->app->when(X::class)->needs('$callable')->give(fn (): Closure => …)` fails at resolution with `BindingResolutionException: Target [Closure] is not instantiable while building [X]`. Laravel's contextual binding only special-cases *primitive* parameters (no class type hint): for a parameter typed `Closure` — or any class — the container takes the class-resolution path and calls `make()` on the given concrete, so a `Closure` value is treated as a class name to instantiate rather than returned as the value. Bind the service itself with a factory closure instead — `$this->app->singleton(X::class, fn (): X => new X($configValue, static fn (): int => …, …))` — which constructs the object directly and evaluates config at resolution time. Injecting a `Closure` is the standard seam for making a global PHP function (e.g. `gc_mem_caches()`, `memory_get_usage()`) fakeable in a unit test.
