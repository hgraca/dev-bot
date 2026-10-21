---
date: 2026-10-21
keywords: ["otel", "opentelemetry-auto-laravel", "span-context", "phpunit", "user.id"]
aliases: ["instrumented request span shadows test span", "Span::getCurrent returns server span", "integration test span not tagged"]
trigger-on: ["opentelemetry-auto-laravel", "span-tagging-middleware", "otel-integration-test"]
---

## Auto-instrumentation shadows an activated test span in HTTP integration tests

When `open-telemetry/opentelemetry-auto-laravel` is active, its `Kernel::handle` pre-hook starts the server span and attaches it to the context, and the post-hook ends/detaches it. A span that a test activates before making the request is therefore no longer `Span::getCurrent()` during the request, so a middleware that tags `Span::getCurrent()` writes to the (possibly non-recording) server span and the test's `InMemoryExporter` never sees the attribute.

The failure is environment-dependent: it appears wherever the extension is loaded with auto-instrumentation enabled. `phpunit.xml` `<env name="OTEL_PHP_DISABLED_INSTRUMENTATIONS" value="all"/>` is too late — the extension reads that variable at RINIT, before PHPUnit's bootstrap. The same test can pass in one project's CI (which sets the variable at workflow level) and fail in another's (which sets only `OTEL_SDK_DISABLED`).

Reliable fixes: activate the test span *inside* the route closure, so it is current when the middleware's `finally` runs regardless of instrumentation; or set `OTEL_PHP_DISABLED_INSTRUMENTATIONS=all` (and `OTEL_SDK_DISABLED=true`) in the process environment — CI workflow or dev container — never only in `.env.phpunit`. Production middleware can also prefer the server span the hook stores at `$request->attributes->get(SpanInterface::class)` over `Span::getCurrent()`.
