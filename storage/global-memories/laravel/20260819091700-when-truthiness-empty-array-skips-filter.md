---
date: 2026-08-19
keywords: ["laravel", "eloquent", "when", "whereIn", "empty-array"]
trigger-on: ["laravel-when-truthiness", "eloquent-when-empty-array"]
---

## `Builder::when($value, …)` uses truthiness, so `[]` skips the filter — use `when($value !== null, …)` for non-null semantics

`Builder::when($value, $closure)` (and the `Conditionable` trait generally) applies the closure only when `$value` is truthy, so an empty array `[]` is falsy and the closure is skipped. If the intent is "apply the filter whenever the argument is non-null", this silently turns an empty list into "no filter" instead of "filter to empty set". E.g. `getStoppedSalesTransporterIds($time, [])` returned every stopped transporter instead of none. Fix: `->when($value !== null, fn ($q) => $q->whereIn('col', $value))` — `null` means no filter, `[]` applies `whereIn('col', [])`, which Laravel compiles to `0 = 1` (always-false → empty result). Always write the `!== null` guard when distinguishing "not provided" from "provided but empty".
