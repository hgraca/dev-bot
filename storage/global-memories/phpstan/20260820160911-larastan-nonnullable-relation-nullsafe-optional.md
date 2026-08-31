---
date: 2026-08-20
keywords: ["phpstan", "larastan", "nullsafe", "optional", "eloquent"]
trigger-on: ["larastan-nullable-relation", "nullsafe-nevernull", "optional-mixed"]
---

## Null-safe access on a non-nullable `@property-read` relation — use explicit null-checks

When an Eloquent model declares `@property-read Related $rel` (non-nullable) but the relation can actually be null at runtime, PHPStan/Larastan types `$model->rel` as non-nullable. `$model->rel?->prop` then triggers `nullsafe.neverNull` ("Using nullsafe property access on non-nullable type"), and `optional($model->rel)->prop` triggers `property.nonObject` ("Cannot access property on mixed") because Larastan resolves `optional()` to `mixed`. The clean fix that satisfies PHPStan and stays null-safe is an explicit guard: `if ($model->rel !== null) { ... $model->rel->prop ... }`. If the `@property-read` is genuinely wrong, prefer fixing the annotation to `Related|null` — but that ripples to every existing `$model->rel->...` call site (now flagged possibly-null), so only do it when the nullable contract is intentional and you'll fix the callers.
