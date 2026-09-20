---
date: 2026-09-16
keywords: ['phpunit', 'collision', 'report', 'segfault', 'error-handler']
trigger-on: ['phpunit-handler-report', 'handler-calls-report', 'phpunit-segfault-exit-139']
---

## A `report()` call in the code under test can segfault PHPUnit through Collision

When code under test calls Laravel's `report($exception)` — typically a handler that logs a failure and carries on — PHPUnit can die with a bare **segfault (exit code 139)**: no failure summary, no stack trace, just a truncated progress line. It looks like a crashed test runner, not a test problem. The only signal is PHPUnit marking the affected tests **risky** with `Test code or tested code did not remove its own error handlers` and `... did not remove its own exception handlers`.

The crash happens inside Collision (`nunomaduro/collision`) when it renders the reported exception, and it also leaks error/exception handlers, which corrupts the **next** test in the same file — producing order-dependent failures that disappear when each test is run alone. That combination (segfault + "passes alone") sends you hunting for test-order bugs or factory randomness when the real cause is the reporting path.

Fix: stop `report()` from reaching Collision by binding a no-op handler for the test:

```php
$handler = Mockery::mock(Illuminate\Contracts\Debug\ExceptionHandler::class);
$handler->shouldReceive('report');
$this->app->instance(Illuminate\Contracts\Debug\ExceptionHandler::class, $handler);
```

The explicit `shouldReceive('report')` matters: a bare `Mockery::mock(ExceptionHandler::class)` throws `BadMethodCallException` on the first `report()` call, which leaks into the following test in exactly the same way. Do not "fix" it by mocking the exception instead — a Mockery-mocked `Exception` also breaks Collision, because `getMessage()` is final and cannot be stubbed.
