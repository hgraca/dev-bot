---
date: 2026-08-07
keywords: ["php", "function_exists", "namespaced", "sentry"]
trigger-on: ["function_exists", "sentry-functions", "namespaced-helper"]
---

## function_exists() requires fully-qualified names for namespaced functions

`function_exists('captureException')` returns false even when `\Sentry\captureException` is available via Composer autoload. PHP's `function_exists()` resolves from the current namespace — unqualified names only check the current namespace and global. Use `function_exists('\Sentry\captureException')` with the fully-qualified name to correctly detect namespaced helper functions.
