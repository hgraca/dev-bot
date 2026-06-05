---
date: 2026-05-18
keywords: ["phpstan", "php", "assertion", "null-narrowing", "eloquent"]
---

## Use Assertion::isInstanceOf() to narrow nullable Eloquent relations for PHPStan

Eloquent relations typed as `Model|null` (e.g. `$invoice->account`) cannot be assigned to a non-nullable property without PHPStan raising `assign.propertyType`. The cleanest fix when the value must be non-null at that point is: assign to a local variable, call `Assertion::isInstanceOf($var, Model::class)`, then assign to the property. This narrows the type to `Model` for PHPStan and adds a runtime guard that throws `AssertionFailedException` (already declared in `@throws`) if the relation is unexpectedly null. Avoid `@var` suppression alone — it silences PHPStan without adding the runtime guard.
