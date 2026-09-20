---
date: 2026-08-31
keywords: ["php", "message-bus", "phpunit", "test-harness", "dispatch"]
trigger-on: ["get-e-message-bus-test-harness"]
---

## get-e/message-bus test harness records commands instead of executing them — assert the dispatch, not the DB

`MessageBusTestCaseTrait::setUpMessageBus()` wraps the container's `CommandDispatcher` (and `EventDispatcher`) in a recording decorator: commands are **logged, not executed** (the "nested messages logged but not executed" behavior). Consequences for tests that drive the bus through a CLI command or HTTP controller:

- `$this->artisan(...)` / `postJson(...)` → the command/controller dispatches via the recording dispatcher → **nothing is persisted**. Assert the dispatch instead: `assertDispatchedSync(CreateX::class, fn (CreateX $c): bool => ...)`.
- The trait helpers `$this->dispatchCommandSync($command)` / `$this->dispatchQuery($query)` are the only paths that actually execute handlers — use them directly for use-case handler tests that need real side effects (DB writes).
- Trying to assert DB state after an artisan/HTTP round-trip silently fails (row missing) — this is the harness working as designed, not a bug.

Identical trap applies to CLI commands that call `dispatchSync`/`dispatchAsync` inside `handle()`.
