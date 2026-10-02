---
date: 2026-09-29
keywords: ["php", "phparkitect", "arkitect", "phpunit"]
trigger-on: ["phparkitect-tests-rules", "test-without-sut"]
---

## A test with no SUT belongs in TestsRules::create(testsWithoutSut: ...), not folded away

When `phparkitect.php` uses `GetE\DevTools\Php\Arkitect\TestsRules::create(testsNamespace: ..., testsWithoutSut: ...)`, the rule requires every test class to map to an `App\*` unit. A test that legitimately has no SUT class — a config-file test, for example — trips it with "should have a matching unit named: 'App\...'". The escape hatch is the `testsWithoutSut` parameter: pass an `IsA(...)` expression naming the exempt test. For more than one, wrap them in `Arkitect\Expression\Boolean\Orx` (`new Orx(new IsA(A::class), new IsA(B::class))`) — the parameter takes a single expression, not a list. Prefer this over folding the test into an unrelated SUT-mapped class.
