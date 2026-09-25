---
date: 2026-09-25
keywords: ["phpunit", "phpstan", "createMock", "narrowing"]
trigger-on: ["phpunit-create-mock-without-expectations"]
---

## PHPUnit 13 notices `createMock` without expectations, and PHPStan narrowing survives `@phpstan-impure`

PHPUnit 13 adds a `PHPUnit Notices: 1` entry — easy to miss in the summary line, and forbidden in suites that disallow notices — when a double created by `createMock()` has no expectations configured. If you are only stubbing (`->method(x)->willReturn(y)`), `createStub()` is the correct call and silences it. Separately, `@phpstan-impure` on a method does change PHPStan's inter-call narrowing — the diagnostic text moves, for example from `with 1 and 1` to `with 1 and int`, which is how you can tell the annotation took effect — but PHPStan may _still_ call a genuinely meaningful assertion redundant: `assertSame(1, <int>)` cannot fail, so it reports `method.alreadyNarrowedType`. When the assertion is the behaviour under test (a cache serving a stale value, say), keep it and add a scoped `// @phpstan-ignore method.alreadyNarrowedType` with the reasoning recorded; deleting the assertion to satisfy the analyser removes the coverage that justified the test.
