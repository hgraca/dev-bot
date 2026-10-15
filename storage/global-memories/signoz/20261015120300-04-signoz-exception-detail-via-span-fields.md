---
date: 2026-10-15
keywords: ["signoz", "query-builder", "exceptions", "status_message", "job_name"]
aliases: ["status_message carries the exception message", "messaging.message.job_name"]
trigger-on: ["signoz-exceptions-query-builder"]
---

## Query Builder can still show exception detail, via span fields rather than span events

Span **events** — where the exception class, message and stack trace are recorded — are not selectable in the Query Builder, so an exceptions panel built there looks useless at first; but the error is also on the span itself, which is selectable: `status_message` (span context) holds the exception message (`No query results for model [App\Models\Laravel\Booking].`, `Trip is not ready for ride creation...`), and on messaging spans `messaging.message.job_name` (attribute context) names the failing job or listener (`App\Jobs\Allocation\AllocateToSupplierJob`, `App\Modules\Integrations\Slack\Listeners\NewRideToBookings`). `code.file.path` and `code.line.number` also exist as span attributes but identify the _instrumentation_ site rather than the throw site — every sampled `code.file.path` was a `vendor/` path and every `code.line.number` was empty — so they cannot substitute for a stack frame. Selecting `timestamp, service.name, status_message, messaging.message.job_name, name, trace_id` yields a linkable feed that still says what failed and where.
