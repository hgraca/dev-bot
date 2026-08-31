---
date: 2026-06-18
keywords: ["docker", "php-fpm", "env", "clear_env"]
trigger-on: ["php-fpm-env-config", "www-conf-env-directives", "docker-php-ext-config", "env-directives-in-dockerfile", "dockerfile-printf-env", "fpm-pool-env-vars"]
---

## PHP-FPM env var configuration in Dockerfile: always set clear_env=no and use hardcoded values

When configuring PHP-FPM worker environment variables in a Dockerfile via `www.conf` `env[]` directives, two rules prevent silent misconfiguration: (1) Set `clear_env = no` explicitly — the PHP-FPM default is `yes`, meaning workers start with empty env and only receive `env[]` values. Without this, Docker Compose env vars (e.g., `PHP_IDE_CONFIG`, `XDEBUG_CONFIG`) never reach workers. (2) Use hardcoded values in `env[]` directives, never `$VAR` references — PHP-FPM's config parser stores values literally via `setenv()` with no expansion. A `printf` with single quotes writing `env[MY_VAR] = $MY_VAR` results in workers receiving the literal string `$MY_VAR`. Pattern: `sed -i "s/^clear_env = yes/clear_env = no/" /usr/local/etc/php-fpm.d/www.conf` followed by `printf '\nenv[MY_VAR] = actualValue\n'` with idempotency guard (`sed -i '/^env\[MY_/d'`) before the printf.
