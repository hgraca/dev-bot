---
name: make-tests
description: "Test commands, strategy, and conventions: make targets, static analysis, test naming, test locations by layer, testing strategy, MUST/MUST NOT rules. Use this skill whenever writing tests, running the test suite, choosing a test strategy, or checking test conventions."
---

# Testing

## When to Apply

- Writing new tests or modifying existing ones
- Running test suite or static analysis
- Choosing test strategy for new feature or layer
- Reviewing test naming, location, or structure

## Test Commands

All `make` commands run from host, execute inside `app` container.

- `make test`: All tests + static analysis (CI-equivalent)
- `make unit`: All unit tests with DB prep (MariaDB, MongoDB, migrations, seeds)
- `make ut`: Unit tests without DB prep (faster for repeated runs)
- `make t TEST=ClassName`: Single test class, no DB prep
- `make t TEST=ClassName::testMethod`: Single test method, no DB prep
- `make t FILE=tests/Path/To/ClassName.php`: Single test file, no DB prep
- `make coverage`: Same as `make unit` but gathers coverage report, both as text output and in `storage/unit-tests/coverage.xml` and `storage/unit-tests/report.xml`

## Static Analysis

- `make static`: All static analysis tools
- `make stan`: Static analysis
- `make arch`: Architectural rules
- `make lint`: Syntax check
- `make cs`: Coding standards fixer
- `make rect`: Code upgrades (e.g. PHP 8.2 to 8.4)
- `make fix`: Runs `make cs` and `make rect`

## Test Databases

Prepared automatically by `make unit`. Manual preparation:

- `APP_ENV='phpunit' make .db-mariadb`: Recreate testing database
- `APP_ENV='phpunit' make .migrate-mariadb-mongodb`: Run test migrations

## Test Naming

Method names describe scenario, not implementation:

- `it_emits_transfer_booked_event_when_booking_is_confirmed`
- `it_returns_404_when_booking_does_not_exist`
- `it_rejects_booking_when_pickup_is_in_the_past`

## Test Locations

- Integration test (boots framework): `tests/Integration/`, mirroring source paths
- Unit test (no framework): `tests/Unit/`, mirroring source paths

| Source                                                                 | Test                                                                          |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `<src-root>/Core/Component/Invoice/Application/UseCase/CreateInvoice/` | `tests/Integration/Core/Component/Invoice/Application/UseCase/CreateInvoice/` |
| `<src-root>/Presentation/Api/Invoice/`                                 | `tests/Integration/Presentation/Api/Invoice/`                                 |
| `<src-root>/Infrastructure/Database/Invoice/`                          | `tests/Integration/Infrastructure/Database/Invoice/`                          |

`<src-root>` is `src` or `app`.
`/` is namespace separator, might differ by programming language.

## What to Test by Layer

**Domain (`tests/Unit/`)**: entity invariants, state transitions, Value Object construction/equality, Domain Service computations, Domain Events emitted

**Application (`tests/Integration/`)**: Command Handler (state change, commands/events emitted, side effects, edge cases), Event Listener (same four), Query Handler (correct read model)

**Presentation (`tests/Integration/`)**: Controller (HTTP status, response shape, dispatched command/query), Validation (422 with correct error shape)

**Infrastructure (`tests/Integration/`)**: Repository (persist/retrieve), External adapters (correct payload, error handling)

**End-to-end (`tests/Integration/`)**: At least one smoke test verifying full pipeline produces expected output

## Testing Strategy

- Controllers: integration test up to use case, mock use case (business logic: command/handler, service, ...)
- All command handlers and event listeners must have integration tests
- DB queries: test as part of encompassing code, unless >2 `where` conditions — then extract to query object and test separately
- Unit tests only when necessary for coverage percentage or for code difficult to cover with integration tests
- Run affected tests after every test update
- Cover all happy paths, failure paths, and edge cases
- Must not remove test files without approval
- Every change must be programmatically tested
- Run minimum number of tests needed while implementing (so its faster)
- Run full test suite (unit tests and static analysis) before committing

## MUST

- Run `make static` before adding or fixing automated tests
- Test all use cases with integration test
- For every parameter of exported function, ensure at least one test passes non-default (non-`undefined`, non-empty, non-zero) value. A 100%-passing suite where every call site uses same default for parameter cannot detect that parameter being silently ignored.

## MUST NOT

- Set tests as skipped — either test is necessary or it should not exist
- Allow warnings, notices, or deprecation notices — use `make ut-debug` to diagnose and fix
- Use mocks unless strictly necessary
- Use anonymous classes for test doubles — extract named fakes (e.g. `InMemoryFooRepository`) in `tests/Support/`
- Pass real project path (repository root, source tree, or any directory under version control) as `directory`, `cwd`, `path`, or equivalent argument to code under test that writes files. Use `fs.mkdtempSync` (or language equivalent) to create per-test temporary directory and pass that. Tests pointing at real paths pollute working state and cause cross-test interference.

## See also

- `makefile` skill
