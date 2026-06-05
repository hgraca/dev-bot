---
name: make-use-case
description: "Generate CQRS Command/CommandHandler pairs, Integration tests covering the CommandHandler, and Unit tests for other introduced services. Use this skill whenever the user wants to create a new UseCase with Command, CommandHandler, and tests following the project's Clean Architecture and MessageBus patterns — even if they do not say 'use case' (e.g. 'add a command to create an invoice', 'wire a new handler')."
---

# Create UseCase Skill

(shamelessly stolen from [Nickita Kirichenko](https://github.com/Kirich11))

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

## Required Information

Before generating, gather from user:

1. **Component name** (e.g. `AutomaticBooking`, `User`)
2. **Command interface** - defaulted to `GetE\MessageBus\Port\CommandBus\Command`, but can be changed by user input
3. **UseCase name** (e.g., `RejectBooking`, `CancelFlight`)
4. **Command properties** - what data command needs
5. **Handler logic** - what handler should do
6. **Dependencies** - which services/dispatchers are needed
7. **Return type** - what command returns (default: `void`)

## Project Structure

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

## Command Template

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

### Command Patterns

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

## CommandHandler Template

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

## CommandValidator Template

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

### Common Dependencies

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

### Handler Patterns

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

## Unit Test Template

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

## Integration Test Template

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

### Test Patterns

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

## Generation Checklist

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

## Imports Reference

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
