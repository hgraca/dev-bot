---
name: phpunit
description: "PHPUnit conventions: test attributes, avoiding risky/slow warnings, handler cleanup, slow test detector, e2e testing pattern for framework-agnostic libraries. Use this skill whenever writing or reviewing PHP tests with PHPUnit."
---

# PHPUnit

## When to Apply

- Writing new PHPUnit test classes or methods
- Reviewing PHP test files for correctness and hygiene
- Debugging risky, slow, or warning-flagged tests
- Writing e2e tests for libraries designed to work across frameworks

## Test Philosophy

- PHPUnit output must report zero warnings, zero notices, and zero risky tests. Every section below explains how to prevent specific issue type.
- Every test must have reason to exist — "What bug would this catch?"
- Tests should be obvious, not clever.
- Test behavior, not implementation.
- Never write tests that only verify class structure through reflection. Tests must exercise code paths and assert observable behavior.

## Test Attributes

Use PHPUnit attributes (not annotations) for all test metadata:

```php
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Large;

#[Test]
public function it_dispatches_the_command(): void { }
```

Do not use `@test`, `@dataProvider`, or `@group` annotations — they are deprecated in PHPUnit 12+.

## Preventing Risky Test Warnings

PHPUnit flags test as **risky** when it detects side effects not cleaned up.

### Error and exception handlers

**Problem**: frameworks like Laravel register custom error/exception handlers via `set_error_handler()` and `set_exception_handler()` during bootstrap. PHPUnit detects these pushed onto handler stack but never removed, producing:

> _Test code or tested code did not remove its own error handlers_  
> _Test code or tested code did not remove its own exception handlers_

**Solution**: snapshot handler stack depth before booting framework, then pop exactly handlers that were added.

```php
private int $errorHandlerDepthBeforeBoot = 0;
private int $exceptionHandlerDepthBeforeBoot = 0;

protected function setUp(): void
{
    parent::setUp();

    $this->errorHandlerDepthBeforeBoot = $this->snapshotErrorHandlerDepth();
    $this->exceptionHandlerDepthBeforeBoot = $this->snapshotExceptionHandlerDepth();

    // ... boot framework / application ...
}

protected function tearDown(): void
{
    // ... tear down framework / application ...

    $added = $this->snapshotErrorHandlerDepth() - $this->errorHandlerDepthBeforeBoot;
    for ($i = 0; $i < $added; $i++) {
        restore_error_handler();
    }

    $addedEx = $this->snapshotExceptionHandlerDepth() - $this->exceptionHandlerDepthBeforeBoot;
    for ($i = 0; $i < $addedEx; $i++) {
        restore_exception_handler();
    }

    parent::tearDown();
}
```

Snapshot helpers drain stack non-destructively (collect all handlers, then re-install in reverse order) to count current depth.

**Why not `set_error_handler($previousHandler)`?** Because `set_error_handler()` _pushes_ new entry — it does not replace. Calling `set_error_handler(PHPUnit's handler)` makes stack one level deeper, not same. Always use `restore_error_handler()` / `restore_exception_handler()` to pop.

### Other common risky-test causes

- **Output during test**: use `$this->expectOutputString()` or `ob_start()`/`ob_end_clean()`
- **Global state mutation**: reset statics and singletons in `tearDown()`
- **No assertions**: every test method must contain at least one assertion

## tearDown Safety — Global State Restoration

When `tearDown()` restores global state (env vars via `putenv()`, static properties, file handles, database state), wrap the restoration in `try {} finally { parent::tearDown(); }` so PHPUnit's own lifecycle cleanup always executes:

```php
protected function tearDown(): void
{
    try {
        putenv('MY_ENV_VAR=' . $this->originalValue);
        // ... other state restoration ...
    } finally {
        parent::tearDown();
    }
}
```

Never place `putenv()` or other state restoration between `try` and `parent::tearDown()` without `finally` — if the restoration throws, PHPUnit's cleanup is skipped, contaminating downstream tests.

## Preventing Slow Test Warnings

This project uses `ergebnis/phpunit-slow-test-detector`. Global threshold is 0.500 seconds.

### `#[MaximumDuration]` attribute

For tests taking longer (real broker I/O, `sleep()` for TTL expiry, etc.), add per-method threshold:

```php
use Ergebnis\PHPUnit\SlowTestDetector\Attribute\MaximumDuration;

#[MaximumDuration(5_000)]
#[Test]
public function it_consumes_from_the_queue(): void { }
```

**`MaximumDuration` targets methods only** (`#[\Attribute(\Attribute::TARGET_METHOD)]`). Cannot be applied at class level — PHP silently ignores misapplied attributes and detector will not read it.

### Budget guidelines

| Test type                                 | Budget                                                                      |
| ----------------------------------------- | --------------------------------------------------------------------------- |
| Unit test (no I/O)                        | Global default (0.500s) — no attribute needed                               |
| Integration test with real DB             | Global default, or `#[MaximumDuration(1_000)]` if timing tight              |
| Test with `sleep()` for TTL/timeout       | Sleep duration + 1s margin (e.g., `sleep(2)` → `#[MaximumDuration(3_000)]`) |
| E2e test with real brokers (Redis, Kafka) | `#[MaximumDuration(5_000)]`                                                 |
| E2e test consuming from Kafka             | `#[MaximumDuration(10_000)]` — Kafka consumer timeout adds latency          |
| Kafka connector integration test          | `#[MaximumDuration(20_000)]` — full broker round-trip                       |

### When to add attribute

Add `#[MaximumDuration]` when writing test, not after slow warning appears. If test interacts with real broker, network service, or uses `sleep()`, it will be slow — tag it proactively.

## Preventing PHPUnit Notices (Mock vs Stub)

PHPUnit 12+ emits notice when mock object has no expectations configured:

> _No expectations were configured for mock object_

**Fix**: if you only need stand-in object returning values, use `createStub()` instead of `createMock()`:

```php
// BAD — triggers notice in PHPUnit 12+
$logger = $this->createMock(LoggerInterface::class);
$logger->method('info')->willReturn(null);

// GOOD — stubs don't expect calls
$logger = $this->createStub(LoggerInterface::class);
$logger->method('info')->willReturn(null);
```

Use `createMock()` only when you actually call `->expects()`.

Do not use `#[AllowMockObjectsWithoutExpectations]` — it suppresses notice instead of fixing root cause.

### Shared test doubles in `setUp()`

When `setUp()` creates test double shared across multiple test methods, use `createStub()` by default. Tests needing expectations create local mock and re-initialize SUT:

```php
use PHPUnit\Framework\MockObject\Stub;

private SomeInterface&Stub $dependency;
private SystemUnderTest $sut;

protected function setUp(): void
{
    parent::setUp();
    $this->initSut($this->createStub(SomeInterface::class));
}

private function initSut(SomeInterface&Stub $dependency): void
{
    $this->dependency = $dependency;
    $this->sut = new SystemUnderTest($dependency);
}

// Test needing expectations — local mock overrides stub:
#[Test]
public function it_calls_the_dependency_exactly_once(): void
{
    $mock = $this->createMock(SomeInterface::class);
    $this->initSut($mock);

    $mock->expects(self::once())->method('execute');

    $this->sut->run();
}
```

Type shared property as `SomeInterface&Stub`, not as `SomeInterface&MockObject`. This tells PHPStan property has both interface methods and `->method()` / `->willReturn()` stub methods. `initSut()` parameter must also use `&Stub` — `MockObject` extends `Stub`, so passing mock to `&Stub` parameter works.

## E2E Testing for Framework-Agnostic Libraries

When library designed to work across multiple frameworks (e.g., Laravel and Symfony), e2e tests must exercise full stack without coupling to any one framework.

### Architecture: Application Factory pattern

1. **Define framework-agnostic interface** (`EndToEndApplicationFactory`) in `tests/e2e/` with methods for all test operations: dispatching, consuming, asserting queue state, managing locks, rate limiters, circuit breakers, etc.

2. **Implement per framework** in `tests/e2e/<Framework>/` (e.g., `tests/e2e/Laravel/LaravelEndToEndApplicationFactory`). Only factory implementation imports framework classes.

3. **Write tests against interface** in `tests/e2e/TestCase/`. Test files import nothing from any framework — only from `tests/e2e/` and library's own ports.

4. **Resolve factory at runtime** via environment variable (e.g., `E2E_APPLICATION_FACTORY`), defaulting to one framework.

```
tests/e2e/
├── EndToEndApplicationFactory.php    # Interface
├── EndToEndTestCase.php              # Base test case (framework-agnostic)
├── Laravel/
│   ├── LaravelEndToEndApplicationFactory.php
│   └── Resolver/                     # E2e-specific config resolvers
├── Symfony/
│   └── SymfonyEndToEndApplicationFactory.php
├── TestCase/                         # All test files (framework-agnostic)
│   ├── CommandDispatcherE2eTest.php
│   └── ...
└── TestMessage/                      # Fixtures (commands, events, handlers)
```

### Key rules

- **Zero framework imports in test files** — only factory interface and library's own ports
- **Separate e2e resolvers from unit test resolvers** — unit tests typically use database broker for queue inspection (`DB::select('select * from jobs')`); e2e tests use real brokers (Redis, Kafka). Sharing resolvers between them causes cross-contamination
- **Handler cleanup in base test case** — see "Preventing Risky Test Warnings" above
- **Architecture rule exclusion** — if project enforces "every test class must have corresponding production unit", exclude `tests/e2e/` from that rule since e2e tests by design have no 1:1 production counterpart

### Factory lifecycle

```
setUp()     → boot() → reset() → [run test]
tearDown()  → tearDown() → [restore handlers] → parent::tearDown()
```

- `boot()`: create application, configure brokers
- `reset()`: flush queues, truncate tables, drain topics — called before each test for isolation
- `tearDown()`: clean up application resources

### Broker-specific considerations

| Broker   | Queue inspection                                   | Consumption                               | Notes                                                            |
| -------- | -------------------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------- |
| Database | `DB::select()` on `jobs` table                     | `Queue::pop()`                            | Full introspection available                                     |
| Redis    | `LRANGE` for pending, `ZCARD`/`ZRANGE` for delayed | `Queue::pop()`                            | Payloads are JSON with `attempts` field                          |
| Kafka    | No peek capability                                 | `KafkaQueue::pop()` with consumer timeout | Use consume + side-effect assertions instead of queue inspection |

## See also

- `make-tests` skill — project-wide test strategy, commands, conventions
- `message-bus` skill — message bus handler testing patterns
- `php-rules` skill — PHP coding conventions
