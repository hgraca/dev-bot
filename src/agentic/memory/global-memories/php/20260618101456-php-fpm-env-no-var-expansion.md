---
date: 2026-06-18
keywords: ["php", "php-fpm", "env"]
---

## PHP-FPM env[] directive stores values literally, does NOT expand $VAR

PHP-FPM's `env[]` configuration directive passes values directly to `setenv()` without any shell-like `$VAR` expansion. If `www.conf` contains `env[MY_VAR] = $MY_VAR`, the PHP worker process receives the literal string `$MY_VAR` (dollar sign included) as the environment variable value, NOT the value of any shell or container environment variable. The config parser in `fpm_conf.c` stores the value verbatim. This matters when generating `env[]` directives via `printf` in Dockerfiles — single-quoted format strings prevent shell expansion at build time (correct), but the resulting literal `$VAR` strings are wrong at runtime. Fix: use hardcoded default values in `env[]` directives, or double-quote the printf string so shell expansion happens at Docker build time (though hardcoded defaults are more predictable).
