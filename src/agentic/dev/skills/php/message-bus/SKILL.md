---
name: message-bus
description: "PHP message bus integration: dispatching commands/events/queries, handler testing patterns, test traits. Use this skill whenever working with the message bus, writing command/event/query handlers, or testing bus-related code."
---

# PHP Message Bus

## When to Apply

- Working with message bus (dispatching commands, events, or queries)
- Writing or modifying command handlers, event listeners, or query handlers
- Writing integration tests for handlers

## MUST

- Before any work involving message bus (dispatching commands/events/queries, writing handlers/listeners, writing bus-related tests),
  read `vendor/get-e/message-bus/README.ai.md` in full

## Handler Integration Tests

- Must dispatch messages through actual `get-e/message-bus` — never instantiate handlers directly
- Use `GetE\MessageBus\Support\Laravel\Test\MessageBusTestCaseTrait` and `QueueTestCaseTrait`:
    - **Command handlers**: `dispatchCommandAsync($command)`, process with `runQueueWorker($queueName)`, assert with `assertDispatched()`
    - **Event listeners**: `dispatchEvent($event, ListenerClass::class)`, assert with `assertDispatched()`
    - **Query handlers**: `dispatchQuery($query)`, assert returned read model
- Nested messages (dispatched by handler under test) logged but not executed — assert with `assertDispatched()`, `assertDispatchedAsync()`, `assertNotDispatched()`
- Use `\GetE\MessageBus\Port\Context\MessageBusContext` when `Context` implementation needed in tests

## See also

- `laravel` skill
- `php-rules` skill
