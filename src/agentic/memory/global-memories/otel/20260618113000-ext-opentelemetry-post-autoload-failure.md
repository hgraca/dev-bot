---
date: 2026-06-18
keywords: ["otel", "composer", "opentelemetry", "post-autoload-dump"]
---

## ext-opentelemetry auto-load fails post-autoload-dump after adding OTEL packages

After adding `open-telemetry/opentelemetry-auto-laravel` to composer.json, the `post-autoload-dump` script fails with "The opentelemetry extension must be loaded" because the package's autoloader tries to register hooks that require the PECL extension. This happens before the PECL extension is installed (Task 3 of the OTEL setup). Workaround: pass `--no-scripts` to `composer update` or `composer install` to skip post-autoload-dump, or use `--ignore-platform-req=ext-opentelemetry` to bypass the extension requirement check. The extension must be installed via PECL before the application can run.
