---
date: 2026-08-11
keywords: ["laravel", "container", "variadic", "contextual-binding", "needs"]
trigger-on: ["laravel-service-provider", "laravel-variadic-constructor", "laravel-contextual-binding"]
---

## Laravel container contextual bindings don't work with variadic constructor params

Laravel's `$app->when()->needs()->give()` contextual binding system cannot deliver values to variadic constructor parameters. Both `->needs('$paramName')` (by name) and `->needs(Type::class)` (by type) fail. With by-name matching, the container never resolves the `give()` closure — the variadic param receives zero arguments. With by-type matching, the container tries to resolve each variadic position individually, producing type errors. Use a typed `array` parameter instead (e.g. `array $middlewares = []`) when the dependency comes from a contextual binding closure that returns an array.
