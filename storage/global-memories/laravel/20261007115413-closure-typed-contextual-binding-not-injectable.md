---
date: 2026-10-07
keywords: ["laravel", "container", "closure", "contextual-binding"]
aliases: ["needs give closure", "inject callable laravel"]
trigger-on: ["laravel-contextual-binding"]
---

## A Closure-typed constructor parameter cannot be injected with needs()->give()

Laravel's container resolves a `Closure`-typed constructor parameter through `resolveClass()`, not `resolvePrimitive()` (`Illuminate/Container/Container.php`): `Util::getParameterClassName()` returns `'Closure'` because `Closure` is a class, so the container runs `make('Closure')`, which is not instantiable and throws `BindingResolutionException`; a contextual binding keyed on the parameter name (`$this->app->when(Foo::class)->needs('$callback')->give(fn () => fn () => 'x')`) is therefore never consulted. Two workarounds: type the parameter `callable` (or leave it untyped) so it flows through `resolvePrimitive()` and the contextual binding is honoured, or bind the class explicitly and construct it by hand — `$this->app->bind(Foo::class, fn ($app) => new Foo(static fn (): Bar => $app->make(Bar::class)))`. Prefer the explicit bind when the parameter must remain a typed `Closure` property, since PHP forbids `callable` as a property type.
