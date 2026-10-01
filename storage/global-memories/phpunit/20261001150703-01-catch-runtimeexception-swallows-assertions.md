---
date: 2026-10-01
keywords: ["phpunit", "runtimeexception", "assertion", "transaction"]
trigger-on: ["phpunit-transaction-assertions"]
---

## catch (RuntimeException) around DB::transaction swallows assertion failures

PHPUnit's `AssertionFailedError` extends `PHPUnit\Framework\Exception`, which extends PHP's `\RuntimeException`. A test that forces a rollback with `try { DB::transaction(function () { /* ...asserts... */ throw new RuntimeException('roll back'); }); } catch (RuntimeException) {}` therefore silently swallows every assertion failure inside the closure — the expectation exception takes the same path as the intended marker, so the test passes even when the asserted value is wrong, and only the assertions after the catch (usually asserting the same value) run. Roll back explicitly instead of catching: `DB::beginTransaction(); try { /* ...asserts... */ } finally { DB::rollBack(); }`, so failures propagate. If a marker is unavoidable, extend `\Exception` (not `RuntimeException`) and catch that exact class.
