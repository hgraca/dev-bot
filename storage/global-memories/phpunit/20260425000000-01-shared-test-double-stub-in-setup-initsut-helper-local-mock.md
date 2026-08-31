---
date: 2026-04-25
keywords: ["phpunit", "mock", "stub"]
---

## Shared test double: stub in setUp, initSut helper, local mock for expectations

When setUp() creates a test double shared across test methods: (1) use `createStub()` by default, (2) extract an `initSut(Interface&Stub $dep)` helper that wires the dependency and SUT, (3) tests needing `expects()` create a local `createMock()` and call `initSut($mock)`. Type the shared property as `Interface&Stub`. This eliminates `#[AllowMockObjectsWithoutExpectations]` and makes test intent explicit. Codified in the `phpunit` skill under "Shared test doubles in setUp()".
