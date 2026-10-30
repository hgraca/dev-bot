---
date: 2026-10-22
keywords: ["phpunit", "mockery", "withArgs", "artisan"]
aliases: ["assert log context", "console exit code test", "PendingCommand exit code"]
---

## Asserting a log call's context, and why `artisan()` sometimes returns an int

To prove a log record carries the context a downstream consumer depends on (e.g. `['exception' => $e]` for OpenTelemetry's `ExceptionWatcher`), a bare `Log::shouldHaveReceived('error')->once()` is not enough — it passes even if the context was dropped. Use Mockery's `withArgs()` with a closure, which receives **all** call arguments positionally:

```php
Log::spy();
Log::shouldHaveReceived('error')
    ->once()
    ->withArgs(self::isFailureLogCarryingTheException(...));

private static function isFailureLogCarryingTheException(string $message, array $context): bool
{
    return str_contains($message, 'Failed') && ($context['exception'] ?? null) instanceof SomeException;
}
```

`signoz` verify a matcher like this has teeth by temporarily deleting the context from the production code and confirming the test errors — a passing `withArgs` proves more than a passing `shouldHaveReceived`.

Related trap in the same area: `$this->artisan('cmd')` returns a `PendingCommand` **only when console output is mocked** (the default). After `$this->withoutMockingConsoleOutput()` it returns the **int exit code** from `Kernel::call()`, which is exactly what output-capturing tests need (`Artisan::output()`), so `$exitCode = $this->withoutMockingConsoleOutput()->artisan('cmd')` followed by `assertSame(Command::FAILURE, $exitCode)` is correct. A reviewer (or a model) may flag this as a bug; cite `Illuminate\Foundation\Testing\Concerns\InteractsWithConsole` — `withoutMockingConsoleOutput()` sets `mockConsoleOutput = false`, and `artisan()` branches on it. Adding `assertIsInt($exitCode)` encodes the invariant and stops the argument recurring.
