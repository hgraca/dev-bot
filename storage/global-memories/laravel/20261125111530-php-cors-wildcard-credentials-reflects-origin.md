---
date: 2026-11-25
keywords: ["laravel", "cors", "php-cors", "supports_credentials", "wildcard"]
aliases: ["CORS origin reflection", "allowed_origins star with credentials", "Access-Control-Allow-Credentials"]
---

## fruitcake/php-cors with a wildcard origin and credentials reflects the request Origin

In `fruitcake/php-cors` v1.4.0 (what Laravel's global `HandleCors` middleware uses), `allowed_origins`
containing `*` sets `allowAllOrigins`, and `CorsService::configureAllowedOrigin()` only emits a literal
`*` when `supportsCredentials` is **false**. With `supports_credentials => true`, it falls through to
the dynamic branch: `isOriginAllowed()` returns true immediately because `allowAllOrigins` short-circuits,
so the request's own `Origin` header is echoed back — together with
`Access-Control-Allow-Credentials: true` and `Vary: Origin`. Reads do not stop at the preflight: the
same reflection appears on ordinary GET responses.

The practical consequence is that Laravel's stock `config/cors.php` idiom — `allowed_origins` from
`env('CORS_ALLOWED_ORIGINS', '*')` plus `supports_credentials => true` — is a reflected-origin
misconfiguration, not an inert combination, and it is easy to clear in review by assuming the library
strips `*` when credentials are enabled. It does not.

Fix by naming origins explicitly per environment and failing closed on an empty list; drop
`supports_credentials` where the API authenticates with bearer tokens. Verify on the wire with a
foreign `Origin` on both GET and OPTIONS — the header set is what a reader needs, not the config.

## A single literal origin is returned to every caller

`configureAllowedOrigin()` has a second shortcut: when exactly one literal origin is configured and no
patterns are set, `isSingleOriginAllowed()` is true and the service sets
`Access-Control-Allow-Origin` to that origin **without looking at the request's Origin**. Every response
carries the allowlist entry, including a response to a foreign page. The browser still blocks the
foreign page because the value does not match its origin, but a test asserting "a foreign `Origin` gets
no ACAO" fails, and the allowlist is advertised to everyone.

Workaround that keeps the list explicit: pass the origins as **patterns** (`allowed_origins_patterns`),
each escaped with `preg_quote`, and leave `allowed_origins` empty. `isSingleOriginAllowed()` is then
false, `configureAllowedOrigin()` takes the dynamic branch, only a matching Origin is echoed, and
`Vary: Origin` is set. An empty list yields no patterns and no header — fail closed.
