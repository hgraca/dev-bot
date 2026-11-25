---
date: 2026-11-25
keywords: ["laravel", "cors", "credentials", "origin-reflection"]
aliases: ["Access-Control-Allow-Origin", "fruitcake php-cors", "wildcard credentials"]
---

## `allowed_origins: ['*']` with `supports_credentials: true` makes Laravel reflect any origin

Laravel's `config/cors.php` with `'allowed_origins' => ['*']` **and** `'supports_credentials' => true` does not send a literal `*`; it echoes the caller's `Origin` and adds `Access-Control-Allow-Credentials: true`, which is the worst of both worlds. The mechanism is in `vendor/fruitcake/php-cors/src/CorsService.php`: the `*` branch requires `!supportsCredentials`, and `isSingleOriginAllowed()` returns false whenever `allowAllOrigins` is true, so control falls through to the line that sets `Access-Control-Allow-Origin` to the request's own `Origin`; the credentials header is then attached unconditionally when `supportsCredentials` is set. Confirm on a running instance with `curl -D - -o /dev/null -H 'Origin: https://attacker.invalid' https://host/api/anything` and look for both headers. Exploitability still depends on the session cookie — the `config/session.php` default `same_site => 'lax'` stops a cross-site `fetch` from carrying it, so the defect is durable but not yet exploitable — so report it with the mitigating control named rather than as an active takeover. Fix with an explicit origin allowlist and `supports_credentials => false`.
