---
date: 2026-09-29
keywords: ["otel", "span-builder", "traceparent", "kafka"]
trigger-on: ["otel-span-parent", "review-otel-span-builder"]
---

## SpanBuilder::setParent(false) is the documented "no parent" sentinel, not a TypeError

In `open-telemetry/api` (verified 1.10.0) `SpanBuilderInterface::setParent()` is typed `ContextInterface|false|null`, and its docblock states "null to use the current context, **false to set no parent**"; the SDK's concrete `SpanBuilder` carries the same union. Passing `false` therefore starts an independent root trace and is the idiomatic way to stop a new span inheriting an ambient long-lived context (e.g. a CLI command span). A code-review bot (Copilot) flagged this call as a `TypeError` and recommended "use the root context" — that is wrong: `false` and an empty root context are equivalent, and the existing test that drives that branch passes. Verify a claim like this against `vendor/open-telemetry/api/Trace/SpanBuilderInterface.php` and the SDK implementation before "fixing" working span-creation code.
