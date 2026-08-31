---
date: 2026-08-07
keywords: ["laravel", "give", "splat", "variadic", "container"]
---

## Laravel container give() does not spread into splat parameters

When using `$app->when(Class::class)->needs('$param')->give(fn() => [...])` with a variadic constructor parameter (`Type ...$param`), the container does NOT spread the array returned by `give()` into individual variadic arguments. The splat parameter receives zero arguments.

**Workaround**: Use a plain `array` parameter (`array $param = []`) with a `@param array<Type> $param` docblock for type information. The `give()` closure returns an array that maps directly to the `array` parameter.

**Why non-obvious**: The `MessageBusMiddleware ...$executionTimeMiddlewares` splat was already in use in `MessageEnvelopeHandlerAbstract` and appeared to work, but only because that class was resolved as a singleton before any contextual `give()` bindings were registered — the container's automatic resolution filled the splat from the registered bindings, not from the `give()` closure.
