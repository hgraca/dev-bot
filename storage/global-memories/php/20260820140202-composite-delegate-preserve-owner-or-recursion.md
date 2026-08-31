---
date: 2026-08-20
keywords: ["php", "composite", "delegation", "recursion", "owner"]
trigger-on: ["php-composite-delegate-owner"]
---

## Composite delegators must preserve the delegated owner — self-delegation recurses

When a composite delegates a call and returns a handle/owner for later routing, it must destructure and forward the owner returned by the child, falling back to the direct child only when the child reports none. Overwriting it with the direct child — `return [$span, $scope, $collector];` instead of `return [$span, $scope, $owner ?? $collector];` — breaks as soon as a composite contains another composite: the inner composite is returned as owner, and the receiver's `endSpan()` routes back to the composite with itself as owner, recursing until the process blows up (observed as a PHP segfault, exit 139 — not a catchable exception). Guard the receiver as well: never delegate to `$owner === $this` (a composite must never hand itself back as its own owner; the guard also fixes the no-owner fallback path, which picks the first tracer-owning collector and would otherwise re-enter a nested composite). Seen in `GetE\MessageBus\Port\Telemetry\CompositeTelemetryCollector` (startSpan/endSpan) on PR #163; the fix is two lines: destructure the delegated owner and pass `$owner ?? $child`, plus `&& $owner !== $this` in the routing check.
