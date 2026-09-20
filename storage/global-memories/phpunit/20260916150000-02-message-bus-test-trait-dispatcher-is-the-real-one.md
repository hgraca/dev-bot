---
date: 2026-09-16
keywords: ['phpunit', 'message-bus', 'assertDispatchedAsync', 'testcase-trait']
trigger-on: ['message-bus-command-dispatch-test', 'assert-dispatched-async', 'assert-not-dispatched']
---

## The message-bus test trait's `$commandDispatcher` is the REAL dispatcher, not the recorder

`get-e/message-bus` ships `MessageBusTestCaseTrait` (used by `Tests\TestCase`), which exposes a `protected CommandDispatcher $commandDispatcher` plus `assertDispatchedAsync()` / `assertDispatched()` / `assertNotDispatched()` helpers. The trap: `$commandDispatcher` is resolved from the container **before** the trait swaps the binding for `CommandDispatcherInMemoryLogDecorator`, so it is the **real** dispatcher. Dispatching through it reaches the real bus and records nothing, and the assertion's own diagnostic gives it away — it prints `Dispatched commands: []` even though the dispatch clearly ran.

The recording decorator is what the **container** resolves. So resolve the class under test from the container (`$this->app->make(SomeObserver::class)`) instead of `new SomeObserver($this->commandDispatcher)`, and the assertions then see the dispatch.

Second trap in the same trait: `$commandDispatcher` is already declared on the trait, so a test class declaring its own `private CommandDispatcher $commandDispatcher` fails at class-load with _"Visibility ... must be the same or less restrictive than `Tests\TestCase::$commandDispatcher`"_. Name your own property something else.
