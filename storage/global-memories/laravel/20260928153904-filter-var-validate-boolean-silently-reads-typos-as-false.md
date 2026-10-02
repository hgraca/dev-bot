---
date: 2026-09-28
keywords: ["laravel", "filter-var", "boolean", "cli", "validation"]
trigger-on: ["artisan-boolean-option", "filter-validate-boolean", "cli-flag-parsing"]
---

## filter_var without FILTER_NULL_ON_FAILURE reads every unrecognised boolean as false

`filter_var($value, FILTER_VALIDATE_BOOLEAN)` returns `true` for `1/true/on/yes` and `false` for `0/false/off/no/''`, but it also returns **`false` for anything it does not recognise** — no error, no warning. So a boolean CLI option parsed this way silently disables whatever it controls: `--enabled=ture`, `--enabled=flase` and an explicitly empty `--enabled=` all read as `false` while the command still exits successfully. That is the worst shape of failure for a flag that gates a feature — the operator believes they enabled it, and the next command reports success.

Either pass `FILTER_NULL_ON_FAILURE` (which yields `null` for unrecognised input) and fail loudly on `null`, or validate the raw string against an explicit accepted set before parsing. Worth knowing too that `filter_var` is not equivalent to Laravel's `boolean` validation rule, which accepts only `[true, false, 0, 1, '0', '1']` (`ValidatesAttributes::validateBoolean`) — so `yes`/`on` pass the CLI but would 422 the matching API endpoint.
