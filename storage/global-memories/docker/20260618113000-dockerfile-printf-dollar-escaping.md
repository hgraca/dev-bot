---
date: 2026-06-18
keywords: ["docker", "printf", "php-fpm", "escaping"]
---

## Dockerfile RUN printf must use \$ to produce literal $ in config files

When using `printf` in a Dockerfile RUN to write environment variable references into a config file (e.g. PHP-FPM `env[VAR] = $VAR` in `www.conf`), escape every `$` as `\$` in the format string. Without escaping, Docker expands `$VAR` at build time as an ARG/ENV lookup — if the variable is not a build arg, it resolves to empty, producing broken config. With `\$`, the literal `$VAR` lands in the file, and the runtime process (PHP-FPM, shell, etc.) resolves it from the container environment at runtime. Example: `printf '\nenv[OTEL_SERVICE_NAME] = \$OTEL_SERVICE_NAME\n' >> /usr/local/etc/php-fpm.d/www.conf`.
