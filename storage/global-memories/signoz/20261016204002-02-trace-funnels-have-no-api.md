---
date: 2026-10-16
keywords: ["signoz", "trace-funnels", "saved-views", "api"]
aliases: ["funnels have no API", "trace_funnels returns html", "funnels UI only"]
trigger-on: ["signoz-trace-funnel"]
---

## SigNoz Trace Funnels have no API — they are UI-only

Every candidate route for trace funnels answers with the SPA's HTML and HTTP **200**: `/api/v1/trace_funnels`, `/api/v2/trace_funnels`, `/api/v1/funnels`, `/api/v2/funnels`, `/api/v1/trace_funnel`. GET and POST behave identically. This is the same failure mode already recorded for the retired dashboard V1 routes — a client that trusts the status code sees success while nothing was written, so **check the content type** (`text/html` means the route does not exist), not the status code.

Consequence: a funnel cannot be created, exported or reviewed as code. Unlike saved views (`GET /api/v2/saved_views` → `{data: [...]}`) and log pipelines, there is no `src/funnels/` content-as-code path; the definition must be clicked in the UI and documented next to it.

Funnel steps correlate **within a single trace** on `service.name` + `span.name`. Two operations that each root their own trace — a queue consumer and a per-minute command, say — therefore **cannot** be sequenced into one funnel. Read the span tree of one real trace before designing steps, or the intended business funnel turns out to be inexpressible.
