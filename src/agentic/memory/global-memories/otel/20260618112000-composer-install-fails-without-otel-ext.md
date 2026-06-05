---
date: 2026-06-18
keywords: ["otel", "composer", "ext-opentelemetry", "post-autoload-dump"]
---

## composer install fails without ext-opentelemetry in post-autoload-dump

`open-telemetry/opentelemetry-auto-laravel` package has a `_register.php` that runs during composer's `post-autoload-dump` event. This file calls `extension_loaded('opentelemetry')` and throws if the extension is missing, failing the entire `composer install` even though packages were already extracted. Workaround: pass `--ignore-platform-req=ext-opentelemetry --no-autoloader` during composer operations before the PECL extension is installed in the Docker/PHP runtime. The `--ignore-platform-req` skips the requirement check, and `--no-autoloader` skips the post-autoload-dump scripts that trigger `_register.php`. Both flags are needed.
