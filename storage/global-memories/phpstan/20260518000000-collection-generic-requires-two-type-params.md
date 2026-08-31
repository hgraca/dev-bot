---
date: 2026-05-18
keywords: ["phpstan", "Collection", "generics", "QueryBus"]
---

## PHPStan: Illuminate Collection generic requires two type parameters

When annotating a class that implements a generic interface with `Collection` as the type argument, always use two type parameters: `Collection<int, ModelClass>` not `Collection<ModelClass>`. PHPStan resolves `Collection<T>` as `Collection&iterable<T>` which does not satisfy `Collection<int, T>` constraints — causing `argument.type` errors on `QueryDispatcher::dispatch()` and similar typed dispatch methods. Fix: change `@implements Query<Collection<ModelClass>>` to `@implements Query<Collection<int, ModelClass>>`.
