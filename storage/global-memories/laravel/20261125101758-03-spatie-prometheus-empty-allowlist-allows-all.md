---
date: 2026-11-25
keywords: ["laravel", "prometheus", "spatie", "access-control"]
aliases: ["allowed_ips", "metrics endpoint exposed", "Spatie\\Prometheus"]
---

## Spatie laravel-prometheus treats an empty `allowed_ips` as allow-all

`spatie/laravel-prometheus` ships its `AllowIps` middleware as a **no-op when the allowlist is empty**: `AllowIps::handle` returns `$next($request)` when `count($allowedIps)` is zero, so the package's own docblock ("All IP's are allowed when empty") is the behaviour — an unset list grants public access rather than denying it. The default `config/prometheus.php` publishes a commented-out placeholder (`// '1.2.3.4'`), which reads like a deny-by-default template and is easy to ship unchanged, leaving the metrics route open behind nothing but its route path name. A 64-hex route path is not access control. Check with `curl -sS -o /dev/null -w '%{http_code}' https://host/prometheus-<hash>`: a `200` without a session is the finding. Confirm the config is `'enabled' => true` and `'allowed_ips' => []`, and that this is committed config rather than an `APP_ENV` artefact. Fix by populating the allowlist with the scraper's addresses, or by putting the route behind `auth` / a network policy when it is only scraped in-cluster.
