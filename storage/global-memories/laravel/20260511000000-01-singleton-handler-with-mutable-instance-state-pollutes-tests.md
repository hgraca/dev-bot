---
date: 2026-05-11
keywords: ["laravel"]
---

## Singleton handler with mutable instance state pollutes tests

Laravel resolves message-bus handlers as singletons. A handler that accumulates results into a `private array $foo = []` instance property never resets between invocations — running it from one test pollutes subsequent tests in the same process with stale entries. Symptom: a dedicated handler test (`GetCustomerInvoiceAndCreditMemoBinaryStringsForInvoiceSummaryHandlerTest`) fails only when a sibling test (`MergeCustomerInvoicesAndCreditMemosForInvoiceSummaryHandlerTest`) runs first; in isolation it passes. Non-obvious because PHPUnit gives a fresh `TestCase` per test, but the Laravel container (and its singletons) survives within the worker.
Fix: Handlers MUST be stateless — `final readonly class … implements QueryHandler` is the project's canonical shape. Use a local `array $acc = []` accumulator in `__invoke` and pass by reference to private helpers (`array &$acc`), or return arrays from helpers and merge. Never store per-invocation accumulators on `$this`. When reviewing a handler, the absence of `readonly` on the class declaration is a smell — check for instance-property mutation in `__invoke`.
