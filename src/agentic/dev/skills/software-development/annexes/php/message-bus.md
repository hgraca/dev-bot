---
name: message-bus
description: "get-e/message-bus (PHP/Laravel) integration: dispatching commands/events/queries, transaction middleware keys, handler testing patterns, test traits, and generating CQRS use cases (Command/CommandHandler/Validator + tests). Read this annex when working with this project's message bus; the stack-independent rules are in annexes/system-design/message-bus.md."
---

# PHP Message Bus

## When to Apply

- Working with `get-e/message-bus` (dispatching commands, events, or queries)
- Writing or modifying command handlers, event listeners, or query handlers
- Reading or changing a project's message bus configuration, including its middleware stacks
- Writing integration tests for handlers
- Creating a new use case (Command + CommandHandler + Validator + tests)

## Annex of `devbot:software-development`

This file is an annex of the `devbot:software-development` hub. Read it only when working with the
message bus or writing bus-related tests. For generic craft — code-quality principles, tests-first
discipline, commit protocol — see `devbot:software-development`; for the technology-neutral bus
rules (transaction boundaries, delivery guarantees, idempotency) see
[`annexes/system-design/message-bus.md`](../system-design/message-bus.md).

## MUST

- Before any work involving message bus (dispatching commands/events/queries, writing handlers/listeners, writing bus-related tests),
  read `vendor/get-e/message-bus/README.ai.md` in full

## Transactions

The design rule — verify, never assume; the pipeline is configuration and a project can lose the
wrapper — is in [`annexes/system-design/message-bus.md`](../system-design/message-bus.md). This is
where the answer lives for `get-e/message-bus`:

1. The project's own `config/message_bus.php`, where the wrapper lives in
   `command_bus.sync_middlewares` (sync commands),
   `command_bus.async_middlewares.execution_middlewares` (async commands) and
   `event_bus.execution_middlewares` (events). The dispatch-time lists
   (`command_bus.async_middlewares.dispatch_middlewares`, `event_bus.dispatch_middlewares`) carry
   logging and context only — never the wrapper.
2. The package default, which applies wherever the key is omitted —
   `vendor/get-e/message-bus/config/message_bus.php`, and the `DEFAULT_SYNC_MIDDLEWARES` /
   `DEFAULT_ASYNC_EXECUTION_TIME_MIDDLEWARES` / `DEFAULT_EXECUTION_TIME_MIDDLEWARES` constants.
3. `TransactionMiddleware` itself, and any substitute or decorator of it — `agent-service` replaces
   it with `LongRunningCommandTransactionMiddleware`, which delegates to the real middleware for every
   command except `ExecuteAgentRun`, deliberately run without a transaction.
4. `transaction.max_nested_transactions` (default `0`, commonly `1` under PHPUnit, which wraps each
   test in a transaction). With a transaction already open — an HTTP controller's `DB::transaction()`,
   a sync listener inside the dispatching handler — `TransactionMiddleware` **skips** and runs the
   handler in the caller's transaction, unless the message implements `RequiresNestedDbTransaction`,
   which forces an inner transaction regardless.

The query bus has no `TransactionMiddleware` of its own: a query handler is **not** wrapped by the
package. It can still run inside a transaction — a query dispatched from an HTTP controller's
`DB::transaction()`, or from a command handler, executes in that caller's transaction — and a project
can add its own query middlewares. Verify the project's query pipeline before relying on either.

When the handler must own a savepoint, implement
`GetE\MessageBus\Port\MessageBus\RequiresNestedDbTransaction` **on the message class** — it extends
`Message`, so it is a marker, not something a handler body calls.

## Handler Integration Tests

- Must dispatch messages through actual `get-e/message-bus` — never instantiate handlers directly
- Use `GetE\MessageBus\Support\Laravel\Test\MessageBusTestCaseTrait` and `QueueTestCaseTrait`:
  - **Command handlers**: `dispatchCommandAsync($command)`, process with `runQueueWorker($queueName)`, assert with `assertDispatched()`
  - **Event listeners**: `dispatchEvent($event, ListenerClass::class)`, assert with `assertDispatched()`
  - **Query handlers**: `dispatchQuery($query)`, assert returned read model
- Nested messages (dispatched by handler under test) logged but not executed — assert with `assertDispatched()`, `assertDispatchedAsync()`, `assertNotDispatched()`
- Use `\GetE\MessageBus\Port\Context\MessageBusContext` when `Context` implementation needed in tests

## Creating a Use Case

_(shamelessly stolen from [Nickita Kirichenko](https://github.com/Kirich11))_

Generate complete CQRS UseCase folder containing:

- **Command** class implementing `GetE\MessageBus\Port\CommandBus\Command`
- **CommandHandler** class implementing `GetE\MessageBus\Port\CommandBus\CommandHandler`
- **Integration test** for CommandHandler
- **Unit tests** covering any additional services introduced by UseCase
- **CommandValidator** class implementing `GetE\MessageBus\Port\CommandBus\CommandValidator`. If argument is entity id - it should exist.

Optionally generate support classes to get needed data in UseCase:

- **Event** class implementing `GetE\MessageBus\Port\EventBus\Event` to throw event in CommandHandler
- **EventHandler** class implementing `GetE\MessageBus\Port\EventBus\EventHandler` to handle event
- **Query** class implementing `GetE\MessageBus\Port\QueryBus\Query` to fetch data needed in CommandHandler
- **QueryHandler** class implementing `GetE\MessageBus\Port\QueryBus\QueryHandler` to execute query to fetch data needed in CommandHandler

### Required Information

Before generating, gather from user:

1. **Component name** (e.g. `AutomaticBooking`, `User`)
2. **Command interface** - defaulted to `GetE\MessageBus\Port\CommandBus\Command`, but can be changed by user input
3. **UseCase name** (e.g., `RejectBooking`, `CancelFlight`)
4. **Command properties** - what data command needs
5. **Handler logic** - what handler should do
6. **Dependencies** - which services/dispatchers are needed
7. **Return type** - what command returns (default: `void`)

### Project Structure

UseCases live in: `app/Core/Component/{ComponentName}/Application/UseCase/{UseCaseName}/`

```
{UseCaseName}/
   {UseCaseName}Command.php
   {UseCaseName}CommandHandler.php
   {UseCaseName}CommandValidator.php
```

Tests live in: `tests/Integration/Core/Component/{ComponentName}/Application/UseCase/{UseCaseName}/`

```
{UseCaseName}/
   {UseCaseName}CommandHandlerTest.php
```

### Command Template

```php
<?php

declare(strict_types=1);

namespace App\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName};

use GetE\MessageBus\Port\CommandBus\Command;

/** @implements Command<{ReturnType}> */
readonly class {UseCaseName}Command implements Command
{
    public function __construct(
        // Add promoted public properties here
        // e.g., public int $bookingId,
    ) {
    }
}
```

#### Command Patterns

**Scalar parameters (most common):**

```php
public function __construct(
    public int $bookingId,
    public string $reason,
)
```

**DTO parameter:**

```php
public function __construct(public SomeDto $dto)
```

**Mixed parameters:**

```php
public function __construct(
    public int $bookingId,
    public Flight $flight,
    public EmployeeData $employee,
)
```

### CommandHandler Template

```php
<?php

declare(strict_types=1);

namespace App\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName};

use GetE\MessageBus\Port\CommandBus\CommandHandler;

/** @implements CommandHandler<{UseCaseName}Command> */
readonly class {UseCaseName}CommandHandler implements CommandHandler
{
    public function __construct(
        // Inject dependencies here
    ) {
    }

    public function __invoke({UseCaseName}Command $command): {ReturnType}
    {
        // Implementation here
    }
}
```

### CommandValidator Template

```php
declare(strict_types=1);

namespace App\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName};

use GetE\MessageBus\Port\CommandBus\CommandValidator

/** @implements CommandValidator<{UseCaseName}Command> */
readonly class {UseCaseName}CommandValidator implements CommandValidator
{
    public function __construct(
        // Inject dependencies here
    ) {
    }

    public function __invoke({UseCaseName}Command $command)
    {
        // Implementation here
    }
}
```

#### Common Dependencies

Import and inject as needed:

```php
use GetE\MessageBus\Port\QueryBus\QueryDispatcher;
use GetE\MessageBus\Port\CommandBus\CommandDispatcher;
use GetE\MessageBus\Port\EventBus\EventDispatcher;
```

**QueryDispatcher** - to fetch data via queries:

```php
$booking = $this->queryDispatcher->dispatch(new FindBookingByIdQuery($command->bookingId));
```

**EventDispatcher** - to emit domain events:

```php
$this->eventDispatcher->dispatch(new BookingRejected($booking->id, $command->reason));
```

**CommandDispatcher** - to dispatch other commands:

```php
$this->commandDispatcher->dispatchAsync(new NotifyUserCommand($booking->user_id));
```

#### Handler Patterns

**Fetch entity and validate:**

```php
$booking = $this->queryDispatcher->dispatch(new FindBookingByIdQuery($command->bookingId));
if ($booking === null) {
    throw new \RuntimeException("Booking not found '{$command->bookingId}'");
}
```

**Update entity state:**

```php
$booking->status = BookingStatus::REJECTED;
$booking->rejection_reason = $command->reason;
$booking->save();
```

**Dispatch events:**

```php
$this->eventDispatcher->dispatch(new BookingRejected(
    bookingId: $booking->id,
    reason: $command->reason,
));
```

### Unit Test Template

```php
<?php

declare(strict_types=1);

namespace Tests\Unit\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName};

use App\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName}\{UseCaseName}Command;
use App\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName}\{UseCaseName}CommandHandler;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class {UseCaseName}CommandHandlerTest extends TestCase
{
    #[Test]
    public function it_handles_command(): void
    {
        // Arrange: Create test data using factories
        // $booking = Booking::factory()->create([...]);

        // Create mocks for dependencies if needed
        // $mockService = $this->createMock(SomeService::class);
        // $mockService->expects($this->once())->method('someMethod');

        // Act: Create and invoke handler
        $handler = new {UseCaseName}CommandHandler(
            // Pass dependencies or mocks
        );

        $command = new {UseCaseName}Command(
            // Pass command properties
        );

        $handler($command);

        // Assert: Verify expected outcomes
        // $this->assertDatabaseHas('bookings', [...]);
        // $this->assertDispatched(SomeEvent::class);
    }
}
```

### Integration Test Template

```php
<?php

declare(strict_types=1);

namespace Tests\Integration\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName};

use App\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName}\{UseCaseName}Command;
use App\Core\Component\{ComponentName}\Application\UseCase\{UseCaseName}\{UseCaseName}CommandHandler;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class {UseCaseName}CommandHandlerTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        $this->setupSyncDispatcher();
    }

    #[Test]
    public function it_handles_command(): void
    {
        // Arrange: Create test data using factories
        // $booking = Booking::factory()->create([...]);

        // Create mocks for dependencies if needed
        // $mockService = $this->createMock(SomeService::class);
        // $mockService->expects($this->once())->method('someMethod');

        // Act: Create and invoke handler
        $command = new {UseCaseName}Command(
            // Pass command properties
        );

        $this->commandDispatcher->dispatchSync($command);

        // Assert: Verify expected outcomes
        // $this->assertDatabaseHas('bookings', [...]);
        // $this->assertDispatched(SomeEvent::class);
    }
}
```

#### Test Patterns

**Database assertions:**

```php
$this->assertDatabaseHas('bookings', [
    'id' => $booking->id,
    'status' => BookingStatus::REJECTED->value,
]);
```

**Event assertions (with MessageBusTestCaseTrait):**

```php
$this->assertDispatched(BookingRejected::class, function ($event) use ($booking) {
    return $event->bookingId === $booking->id;
});
```

**Exception assertions:**

```php
$this->expectException(\RuntimeException::class);
$this->expectExceptionMessage("Booking not found");
```

**Mocking dependencies:**

```php
$queryDispatcher = $this->createMock(QueryDispatcher::class);
$queryDispatcher->expects($this->once())
    ->method('dispatch')
    ->willReturn($booking);
```

### Generation Checklist

When generating UseCase:

1. Create UseCase folder in `app/Core/Component/{ComponentName}/Application/UseCase/`
2. Generate Command class with:
   - Correct namespace
   - `readonly` modifier
   - `Command` or user-given interfaces
   - PHPDoc with `@implements Command<ReturnType>`
   - Constructor with promoted properties
3. Generate CommandHandler class with:
   - Correct namespace
   - `readonly` modifier (unless state mutation needed)
   - `CommandHandler` interface
   - PHPDoc with `@implements CommandHandler<CommandClass>`
   - Constructor with required dependencies
   - `__invoke` method with implementation
4. Create test folder in `tests/Integration/Core/Component/{ComponentName}/Application/UseCase/`
5. Generate Integration test class with:
   - Correct namespace
   - `setUp()` calling `setupSyncDispatcher()`
   - At least one test method with `#[Test]` attribute
   - Proper arrange/act/assert structure

### Imports Reference

Common imports for Commands:

```php
use GetE\MessageBus\Port\CommandBus\Command;
```

Common imports for Handlers:

```php
use GetE\MessageBus\Port\CommandBus\CommandHandler;
use GetE\MessageBus\Port\QueryBus\QueryDispatcher;
use GetE\MessageBus\Port\EventBus\EventDispatcher;
use GetE\MessageBus\Port\CommandBus\CommandDispatcher;
```

Common imports for Tests:

```php
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;
```

## See also

- `annexes/php/laravel.md`
- `annexes/php/php-rules.md`
