---
date: 2026-08-19
keywords: ["phpstan", "eloquent", "pluck", "cast.int", "Collection"]
trigger-on: ["phpstan-cast-int", "eloquent-pluck-typing", "collection-generics"]
---

## Eloquent `pluck()` is `Collection<int, mixed>`; narrow with `assert(is_int())` for a typed int collection

`Builder::pluck('column')` is typed `Collection<int, mixed>` because PHPStan cannot infer the column type, so a `@return Collection<int, int>` annotation fails with `return.type`. Neither cast works on the scalar: `(int) $id` trips `cast.int` ("Cannot cast mixed to int") and `intval($id)` trips `argument.type` (PHPStan types `intval`'s param as a union that excludes `object`). Hydrating models (`->get()->map(fn (Rule $r) => $r->transporter_id)`) satisfies PHPStan but adds model-hydration overhead in hot paths — reviewers flagged this. Best fix: keep scalar `pluck` and narrow inside the map closure with an assertion, `->pluck('transporter_id')->map(static function (mixed $id): int { assert(is_int($id)); return $id; })`. `assert(is_int($id))` narrows `mixed` to `int` so the return is typed, yielding `Collection<int, int>` with no cast, no model hydration, and no baseline entry. This `assert(is_int($id))` narrowing is an established codebase pattern (e.g. `CreateSupplierPayoutStatementSpreadsheetHandler.php`).
