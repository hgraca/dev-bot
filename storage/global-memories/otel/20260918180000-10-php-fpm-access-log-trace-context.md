---
date: 2026-09-18
keywords: ["otel", "php-fpm", "access-log", "trace-id"]
trigger-on: ["php-fpm-access-log", "fastcgi-trace-id", "nginx-fpm-tracing"]
---

## PHP-FPM's access log can surface nginx's trace context via FastCGI params

nginx can be set to `otel_trace on` and forward its trace ids as FastCGI parameters (`fastcgi_param TRACE_ID $otel_trace_id;` and `fastcgi_param SPAN_ID $otel_span_id;`); PHP-FPM then reads them back in `www.conf` with `access.log = /proc/self/fd/2` and `access.format = "... trace_id=%{TRACE_ID}e span_id=%{SPAN_ID}e"`. This yields per-request log lines carrying the trace id with no PHP code at all, and is a quick way to prove end-to-end trace propagation works without a collector attached. Because PHP-FPM clears the environment before workers spawn, any env-var-based config must still be passed through explicitly via `env[...]` lines in `www.conf`.
