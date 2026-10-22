---
date: 2026-10-22
keywords: ["laravel", "casts", "dates", "upgrade", "eloquent"]
trigger-on: ["laravel-major-upgrade", "eloquent-model-change"]
---

## Laravel 10 removed $dates and silently stops casting to Carbon

Laravel 10 dropped support for the `protected $dates` property. Models that still declare it keep working — no error, no deprecation in tests — but the attributes are no longer cast, so they come back as raw database strings instead of `Carbon` instances.

The damage is silent and often API-visible: anything that serialises the attribute changes from ISO-8601 (`2026-10-22T08:00:00.000000Z`) to the database format (`2026-10-22 08:00:00`), and `->diffForHumans()`, `->isPast()` and friends fail or behave differently.

Convert every `$dates` entry into a `$casts` entry with `'datetime'` (`'date' => 'datetime'`), merging with any existing `$casts` rather than replacing it. Neither PHPStan nor a green test suite reliably catches this — grep for `$dates` across `app/` on any Laravel ≥10 upgrade.
