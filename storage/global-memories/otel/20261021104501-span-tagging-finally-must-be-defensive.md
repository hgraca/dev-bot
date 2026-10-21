---
date: 2026-10-21
keywords: ["otel", "middleware", "finally", "error-handling", "user.id"]
aliases: ["telemetry breaks the request", "finally masks route exception", "span tagging error path"]
trigger-on: ["span-tagging-middleware", "otel-middleware", "request-user-resolution"]
---

## Tagging spans in a middleware finally must never change the request outcome

A global middleware that tags the active span with a request-derived identity should do the work in a `finally` block so failed requests are attributed too — but every part of it can throw: `$request->user()` can hit the database or a guard, `getAuthIdentifier()` can throw, `setAttribute` can fail. An exception raised in `finally` replaces the in-flight exception or turns a valid response into a 500; observability must never alter the outcome.

Wrap the resolver call and the tagging in their own `try { } catch (Throwable) { }` (the resolver call sits outside the tagger, so the tagger's catch does not cover it). Test both cases: a throwing resolver still returns the response, and a throwing route still propagates its own exception unchanged.

Resolve the identity *before* any step that can legitimately throw — an authentication middleware that looks up a related record with `firstOrFail()` must call `$request->setUserResolver(...)` first, otherwise the 404/500 response, the one most worth attributing, loses `user.id`.
