---
date: 2026-06-19
keywords: ["otel", "paratest", "phpunit", "laravel", "opentelemetry"]
trigger-on: ["otel-auto-laravel", "paratest-workers", "opentelemetry-php-extension"]
---

## SUPERSEDED by `20260623150100-otel-env-vars-must-be-shell-env-not-dotenv-or-phpunit-xml.md`

Original description retained for context: OTEL auto-laravel `_register.php` hooks installed unconditionally cause PHPUnit/ParaTest worker segfaults (WorkerCrashedException / "Premature end of PHP process").

When `open-telemetry/opentelemetry-auto-laravel` is installed via composer, its `_register.php` file runs on every PHP process via `composer.json autoload.files`, calling `LaravelInstrumentation::register()` which installs C-extension hooks on 10 Laravel core classes. Even when `OTEL_PHP_AUTOLOAD_ENABLED=false` (default) prevents SDK initialization, the hooks are still installed. **Previous fix recommendation (add to `.env.phpunit`) is incorrect for CLI PHP** — the OTEL SDK reads these env vars at Composer autoload time (via `getenv()`), before Laravel loads `.env.phpunit` and before PHPUnit processes `phpunit.xml`. The env vars must be set in the OS shell environment before PHP starts. See superseding entry for correct fix.
