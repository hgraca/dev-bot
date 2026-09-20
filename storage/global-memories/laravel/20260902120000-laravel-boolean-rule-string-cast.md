---
date: 2026-09-02
keywords: ["laravel", "validation", "boolean", "filter_var", "cast"]
trigger-on: ["laravel-boolean-rule-string-cast"]
---

## Laravel's `boolean` rule accepts `'0'`/`'1'` strings — a `(bool)` cast turns `'0'` into `true`

Laravel 12's `boolean` validation rule accepts `[true, false, 0, 1, '0', '1']` (vendor `ValidatesAttributes::validateBoolean`) — not the words `"true"`/`"false"`. A getter that normalizes the validated input with `(bool) $value` therefore turns the accepted string `'0'` into `true` (any non-empty string is truthy), silently enabling a flag the client asked to disable. Normalize with `filter_var($value, FILTER_VALIDATE_BOOLEAN)` (absent → keep `null` for tri-state) so `'0'` → `false`, `'1'` → `true`. The same trap applies to CLI boolean options parsed with `!== '0'` / `=== '1'` comparisons: `--enabled=false` yields the string `'false'`, which `!== '0'` treats as enabled — use `filter_var` there too.
