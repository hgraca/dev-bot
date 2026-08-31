---
date: 2026-05-06
keywords: ["phpunit", "mock", "test"]
---

## Mockery cannot mock `readonly class`

PHP `readonly class` (8.2+) blocks subclass creation at the engine level. Mockery's default `mock(Foo::class)` creates a runtime subclass — for a readonly class this triggers a fatal `Cannot declare class ... because the parent class is readonly`. Symptom: `UpsertSalesOrderServiceTest`-style infinite loop or fatal during test bootstrap. Non-obvious because: (a) error message points at Mockery internals, not the readonly modifier; (b) some readonly classes appear mockable when only their interface is mocked (e.g. `CurrencyServiceTest` worked while `UpsertSalesOrderServiceTest` crashed — same class, different mock target).
Fix: Before inlining/removing an interface on a readonly class, audit ALL test consumers. Options: (1) keep the interface (mock the interface, not the class); (2) drop `readonly` from the class; (3) write a hand-rolled fake. Plans that propose "inline this interface" MUST include an explicit test-double strategy when the concrete is `readonly`.
