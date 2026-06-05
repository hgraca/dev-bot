---
date: 2026-06-22
keywords: ["laravel", "env", "config", "phpunit", "putenv"]
trigger-on: ["laravel-config-testing", "laravel-env-putenv"]
---

## Laravel config cached at boot — putenv() cannot reverse env() decisions in tests

Laravel evaluates `env()` calls in config files at boot time and caches results in the Config repository. Subsequent `putenv()` or `$_ENV` mutations do not affect `config()` return values. Worse, re-requiring the config file (`require config_path(...)`) may still return stale values because `$_ENV` takes priority over `getenv()` in `Env::get()`, and the string `'false'` is truthy in PHP so a ternary like `env('X', false) ? A : B` always takes branch A when the env var is the literal string `'false'`. Laravel's `Env::get()` switch-case normalises `'true'`/`'false'` to booleans, but ONLY when the value comes from `getenv()` — `$_ENV` values bypass that path. Fix: use `config()->set()` to directly program the config to the expected value for each test scenario.
