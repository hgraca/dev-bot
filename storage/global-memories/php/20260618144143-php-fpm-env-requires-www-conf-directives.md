---
date: 2026-06-18
keywords: ["php", "php-fpm", "environment", "www.conf", "docker"]
trigger-on: ["php-fpm-env-config", "fpm-www-conf-env"]
---

## PHP-FPM does not inherit shell environment variables — must forward via env[] directives in www.conf

PHP-FPM workers do not automatically inherit environment variables from the shell or container runtime. To make environment variables available to PHP-FPM, you must explicitly add `env[VAR_NAME] = $VAR_NAME` directives to the pool configuration file (`/usr/local/etc/php-fpm.d/www.conf`). In Dockerfiles, append these with `printf` chained via `&&` in the same RUN layer: `printf '\nenv[OTEL_PHP_AUTOLOAD_ENABLED] = $OTEL_PHP_AUTOLOAD_ENABLED\n...' >> /usr/local/etc/php-fpm.d/www.conf`. Variables resolve at container runtime since `$VAR_NAME` is literal in www.conf (not expanded at build time). Without these directives, `getenv()` calls inside PHP-FPM workers return empty for variables that are set in the container environment.
