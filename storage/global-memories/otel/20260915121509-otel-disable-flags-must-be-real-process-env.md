---
date: 2026-09-15
keywords: ["otel", "phpunit", "env", "opentelemetry", "segfault"]
trigger-on: ["otel-test-config", "phpunit-otel-segfault", "php-fpm-env-config"]
---

## OTEL disable flags only take effect as real process environment — dotenv and phpunit.xml are applied too late

The OpenTelemetry PHP extension reads `OTEL_SDK_DISABLED` and `OTEL_PHP_DISABLED_INSTRUMENTATIONS` when the module initialises (RINIT), before any userland code runs. Every later source is therefore ineffective: a Laravel `.env`/`.env.phpunit` value (loaded by dotenv during bootstrap) or a PHPUnit `<env>` entry (applied by PHPUnit's own bootstrap) arrives after the extension has already decided to instrument. With auto-instrumentation still active, PHPUnit can die mid-run with "Premature end of PHP process" and, because the failing path recurses through the logger, write an unbounded log — observed as a 21 GB `storage/logs/laravel.log` within minutes. Disable it for tests with genuine process environment: the CI job env, `docker exec -e OTEL_SDK_DISABLED=true -e OTEL_PHP_DISABLED_INSTRUMENTATIONS=all …`, a Makefile recipe prefix (`$(OTEL_DISABLED) vendor/bin/phpunit …`), or the service `environment:` in compose. `php -d` does not help — that sets ini, not env. Setting the flags only in dotenv/phpunit.xml gives false assurance: the config looks correct while the extension stays active.
