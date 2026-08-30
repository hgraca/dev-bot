---
name: devbot:make-tests
description: "Test strategy and conventions independent of language or test framework: what to test by layer, integration vs unit placement, naming, and MUST/MUST NOT rules. Use this skill whenever writing tests, choosing a test strategy, or reviewing test structure and conventions."
---

# Testing

## When to Apply

- Writing new tests or modifying existing ones
- Choosing test strategy for new feature or layer
- Reviewing test naming, location, or structure

## Running Tests

Prefer the project's own test commands where they exist (check the project's `Makefile`, package scripts, or `project.md`). This skill defines _what_ to test and _where_; it does not prescribe how to invoke the test runner — that is project-specific.

## Test Naming

Method names describe scenario, not implementation:

- `it_emits_transfer_booked_event_when_booking_is_confirmed`
- `it_returns_404_when_booking_does_not_exist`
- `it_rejects_booking_when_pickup_is_in_the_past`

## Test Locations

- Integration test (boots framework): `tests/Integration/`, mirroring source paths
- Unit test (no framework): `tests/Unit/`, mirroring source paths

| Source                             | Test                                      |
| ---------------------------------- | ----------------------------------------- |
| `<src-root>/<Layer>/<Feature>/...` | `tests/Integration/<Layer>/<Feature>/...` |
| `<src-root>/<Layer>/<Feature>/...` | `tests/Unit/<Layer>/<Feature>/...`        |

`<src-root>` is `src` or `app`. `/` is namespace separator, might differ by programming language.

## What to Test by Layer

**Domain (`tests/Unit/`)**: entity invariants, state transitions, Value Object construction/equality, Domain Service computations, Domain Events emitted

**Application (`tests/Integration/`)**: Use-case handler (state change, commands/events emitted, side effects, edge cases), Event handler (same four), Query handler (correct read model)

**Presentation (`tests/Integration/`)**: Endpoint/controller (HTTP status, response shape, dispatched command/query), Validation (error response shape)

**Infrastructure (`tests/Integration/`)**: Repository (persist/retrieve), External adapters (correct payload, error handling)

**End-to-end (`tests/Integration/`)**: At least one smoke test verifying full pipeline produces expected output

## Testing Strategy

- Controllers: integration test up to use case, mock use case (business logic: command/handler, service, ...)
- All use cases and event handlers must have integration tests
- DB queries: test as part of encompassing code, unless >2 `where` conditions — then extract to query object and test separately
- Unit tests only when necessary for coverage percentage or for code difficult to cover with integration tests
- Run affected tests after every test update
- Cover all happy paths, failure paths, and edge cases
- Must not remove test files without approval
- Every change must be programmatically tested
- Run minimum number of tests needed while implementing (so its faster)
- Run full test suite (unit tests and static analysis) before committing

## MUST

- Run static analysis before adding or fixing automated tests
- Test all use cases with integration test
- For every parameter of exported function, ensure at least one test passes non-default (non-`undefined`, non-empty, non-zero) value. A 100%-passing suite where every call site uses same default for parameter cannot detect that parameter being silently ignored.

## MUST NOT

- Set tests as skipped — either test is necessary or it should not exist
- Allow warnings, notices, or deprecation notices — diagnose and fix them
- Use mocks unless strictly necessary
- Use anonymous classes for test doubles — extract named fakes (e.g. `InMemoryFooRepository`) in `tests/Support/`
- Pass real project path (repository root, source tree, or any directory under version control) as `directory`, `cwd`, `path`, or equivalent argument to code under test that writes files. Use `fs.mkdtempSync` (or language equivalent) to create per-test temporary directory and pass that. Tests pointing at real paths pollute working state and cause cross-test interference.

## See also

- `test-driven-development` skill
