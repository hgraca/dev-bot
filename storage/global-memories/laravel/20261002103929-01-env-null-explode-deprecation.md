---
date: 2026-10-02
keywords: ["laravel", "env", "php84", "deprecation", "explode"]
trigger-on: ["laravel-env-null-internal-param", "php84-null-to-non-nullable"]
---

## `explode(',', env('X'))` is a PHP 8.4 deprecation when X is unset

Laravel's `env()` returns `null` for an unset key, and passing that null to a non-nullable internal
function parameter (`explode`, `strlen`, …) is deprecated in PHP 8.4. A config line such as
`'host' => explode(',', env('MONGODB_HOST'))` therefore prints
`PHP Deprecated: explode(): Passing null to parameter #2 ($string) of type string is deprecated` on
every boot where the variable is absent — and because Rector/PHPStan boot the app, the warning shows
up in static-analysis output and looks like a Rector problem. `explode(',', (string) env('X'))`
silences it while preserving the exact `['']` result of the old null coercion; `env('X', 'fallback')`
is the alternative when an actual default is wanted. The same class of failure applies to any config
file that feeds an unguarded `env()` straight into a non-nullable internal function.
