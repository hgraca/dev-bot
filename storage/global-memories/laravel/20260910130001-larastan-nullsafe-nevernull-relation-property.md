---
date: 2026-09-10
keywords: ["laravel", "larastan", "phpstan", "eloquent", "nullsafe"]
trigger-on: ["larastan-nullsafe-nevernull-relation", "phpstan-nullsafe-relation-property"]
---

## larastan infers Eloquent relation properties as non-null — `?->` triggers nullsafe.neverNull

larastan types a relation property access (`$trip->transporter`, including `HasOne`/`HasOneThrough`) as the related model, not nullable, even though it returns null when no related row exists. Nullsafe access on it therefore fails PHPStan with `nullsafe.neverNull` ("Using nullsafe property access on non-nullable type ... Use -> instead"). Options: (a) call the relation and use the builder's nullable result — `$trip->transporter()->first()?->integration` (PHPStan types `first()` as `TModel|null`, so `?->` is accepted); (b) add the error to `phpstan-baseline.neon` (common where many `nullsafe.neverNull` false-positives are already baselined). Prefer (a): it keeps the null-guard real without weakening the baseline. The nullsafe is genuinely needed at runtime, so do not "fix" it by switching to `->`.
