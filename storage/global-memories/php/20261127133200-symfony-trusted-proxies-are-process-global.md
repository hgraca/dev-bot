---
date: 2026-11-27
keywords: ["php", "phpunit", "symfony", "trusted-proxies", "http-foundation"]
aliases: ["setTrustedProxies", "ip() returns gateway", "X-Forwarded-For test flake"]
trigger-on: ["symfony-request-ip", "phpunit-global-state"]
---

## Symfony's trusted-proxy list is process-global and leaks between tests

`Request::setTrustedProxies()` and `setTrustedHeaderSet()` write static state on `Symfony\Component\HttpFoundation\Request`. Laravel's `TrustProxies` middleware sets it from config on every kernel request, so in a PHPUnit process the value left behind by any earlier feature/HTTP test persists into later unit tests that build a bare `Request::create()`.

Consequence: an assertion that `$request->ip()` equals `REMOTE_ADDR` passes alone and fails when another test ran first — under paratest the ordering is scheduling-dependent, so the suite goes red intermittently. A bare `Request::create()` honours whatever proxy list the previous test left.

Fix: make the state explicit per test — snapshot `Request::getTrustedProxies()` and `getTrustedHeaderSet()`, call `Request::setTrustedProxies()` for the case under test, and restore both in `finally`. Cover both directions (empty list → `REMOTE_ADDR`; list containing `REMOTE_ADDR` → the forwarded value): the pair is discriminating, a single hardcoded expectation is not.
