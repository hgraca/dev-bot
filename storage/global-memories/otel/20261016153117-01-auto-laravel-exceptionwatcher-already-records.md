---
date: 2026-10-16
keywords: ["otel", "opentelemetry-auto-laravel", "exceptionwatcher", "signoz-exceptions", "laravel"]
aliases: ["recordException duplicate", "exceptions tab empty", "exception span event missing"]
trigger-on: ["opentelemetry-auto-laravel", "signoz-exceptions-tab", "withExceptions-otel-hook"]
---

## opentelemetry-auto-laravel already records exceptions on the active span

Before adding an app-side exception hook (`$exceptions->report(...)` or a custom handler that calls
`recordException`), check the auto-instrumentation — the contrib package **already does this**.
`open-telemetry/opentelemetry-auto-laravel` ships an `ExceptionWatcher` (present since 1.3.0),
registered through the `Illuminate\Foundation\Application::__construct` hook. It listens on the
`MessageLogged` event and, when `$log->context['exception']` is a `Throwable` and an OTel context
scope exists, calls `Span::fromContext($scope->context())->recordException($e)` and
`setStatus(StatusCode::STATUS_ERROR, $e->getMessage())`.

Because Laravel's `Handler::reportThrowable()` logs every reported exception with
`context['exception'] = $e`, reported exceptions are already recorded as `exception` span events —
so a `$exceptions->report()` hook that repeats it doubles the event on every error. The watcher
no-ops only when there is no active context scope (an error thrown outside any instrumented
request/job), which is also why errors surfaced only as span status (`has_error`, `status_message`)
may carry no `exception.type`.

Confirm empirically before writing app code: check whether `exception.type` already appears on spans
for the service. Note that an empty SigNoz Exceptions tab is not proof that recording is missing —
it can equally mean the service produced no exceptions, or that span events are not being surfaced
as queryable `exception.type` fields (a collector/ingestion concern, not application code).
