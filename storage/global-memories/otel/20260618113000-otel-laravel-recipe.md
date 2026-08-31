# Add OpenTelemetry to a PHP/Laravel Project — Reusable Prompt

Paste this prompt into DevBot (or any LLM coding agent) in a PHP/Laravel project to replicate the OpenTelemetry integration from the hotels-api commit `6260d0a` (ARC-761).

---

## Prompt

```
Add OpenTelemetry distributed tracing to this Laravel project. Follow this exact recipe:

### 1. Composer packages

Add the following packages to `composer.json` (require section):

- `open-telemetry/exporter-otlp` (^1.4.0)
- `open-telemetry/opentelemetry-auto-laravel` (^1.7.0)
- `open-telemetry/sdk` (^1.14.0)
- `php-http/guzzle7-adapter` (^1.1.0)

Add `tbachert/spi` to `composer.json` → `config.allow-plugins` as `true`.

Run `composer update` to install.

### 2. Environment variables

Add these OTEL_* env vars to every environment file used by the project (.env.dist, .env.phpunit, .env.production, .env.staging, .env.dev, .env.local — check which ones exist and add to all):

```

OTEL_PHP_AUTOLOAD_ENABLED=<true|false depending on env>
OTEL_TRACES_EXPORTER=otlp
OTEL_SERVICE_NAME=<project-name>
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_EXPORTER_OTLP_ENDPOINT=<your-otel-collector-endpoint>

````

Rationale per env:
- **local/dev/phpunit**: `OTEL_PHP_AUTOLOAD_ENABLED=false` (avoid noise during local dev)
- **staging/production**: `OTEL_PHP_AUTOLOAD_ENABLED=true`
- endpoint varies by env too (local dummy vs cluster-local collector)

### 3. Docker (if project uses Docker)

#### 3a. Dockerfile(s) — install the opentelemetry PECL extension

In every PHP-FPM Dockerfile (dev + prod), in the RUN block that calls `pecl install`:

- Add `opentelemetry` to the `pecl install` command
- Add `opentelemetry` to the `docker-php-ext-enable` command

Example change:
```diff
- pecl install rdkafka-6.0.5 redis-6.1.0 mongodb-2.3.3
- docker-php-ext-enable gd soap rdkafka redis mongodb
+ pecl install rdkafka-6.0.5 redis-6.1.0 mongodb-2.3.3 opentelemetry-1.2.1
+ docker-php-ext-enable gd soap rdkafka redis mongodb opentelemetry
````

#### 3b. Dockerfile(s) — forward OTEL env vars to PHP-FPM

In the same Dockerfile, after the line that edits `www.conf` (the `sed` line updating `chdir`), append the OTEL_* environment variables as `env[...]` directives so PHP-FPM workers can see them:

```dockerfile
&& printf '\nenv[OTEL_PHP_AUTOLOAD_ENABLED] = $OTEL_PHP_AUTOLOAD_ENABLED\nenv[OTEL_SERVICE_NAME] = $OTEL_SERVICE_NAME\nenv[OTEL_TRACES_EXPORTER] = $OTEL_TRACES_EXPORTER\nenv[OTEL_EXPORTER_OTLP_PROTOCOL] = $OTEL_EXPORTER_OTLP_PROTOCOL\nenv[OTEL_EXPORTER_OTLP_ENDPOINT] = $OTEL_EXPORTER_OTLP_ENDPOINT\n' >> /usr/local/etc/php-fpm.d/www.conf
```

#### 3c. docker-compose — pass OTEL env vars to the app service

In the app/php service definition in `compose.dev.yml` (or equivalent), add the OTEL_* environment variables with default values:

```yaml
OTEL_PHP_AUTOLOAD_ENABLED: "${OTEL_PHP_AUTOLOAD_ENABLED:-true}"
OTEL_SERVICE_NAME: "${OTEL_SERVICE_NAME:-<project-name>}"
OTEL_TRACES_EXPORTER: "${OTEL_TRACES_EXPORTER:-otlp}"
OTEL_EXPORTER_OTLP_PROTOCOL: "${OTEL_EXPORTER_OTLP_PROTOCOL:-http/protobuf}"
OTEL_EXPORTER_OTLP_ENDPOINT: "${OTEL_EXPORTER_OTLP_ENDPOINT:-https://<your-collector-host>}"
```

### 4. Verify

After completing all steps:

1. Rebuild Docker images (`docker compose build`)
2. Start the stack
3. Check `php -m | grep opentelemetry` inside the container to confirm the extension loaded
4. Make a test HTTP request and verify traces appear in your tracing backend (e.g. SigNoz, Jaeger, Grafana Tempo)

### Important notes

- The `opentelemetry-auto-laravel` package provides zero-config auto-instrumentation — after installing the extension and packages, traces should appear automatically for HTTP requests, database queries, and cache operations.
- The PECL extension is the native PHP instrumentation layer; the composer packages provide the SDK, Laravel auto-instrumentation, and the OTLP exporter.
- `php-http/guzzle7-adapter` is needed because the OTLP exporter uses PSR-18 HTTP client abstraction and Guzzle is the concrete implementation.
- `tbachert/spi` is needed for service discovery of instrumentation hooks.
- PHP-FPM does NOT inherit environment variables from the shell by default — hence the explicit `env[...]` directives in `www.conf`.

```

---

## Notes for the user

- Replace `<project-name>`, `<your-otel-collector-endpoint>`, and `<your-collector-host>` with project-specific values.
- If the project doesn't use Docker, skip Section 3 and just ensure the PECL extension is installed on the target PHP runtime directly.
- The `composer.lock` will see a large diff (~900 lines) — that's expected because OpenTelemetry packages pull in many transitive dependencies.
```
