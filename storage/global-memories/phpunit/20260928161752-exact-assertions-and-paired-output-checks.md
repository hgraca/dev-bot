---
date: 2026-09-28
keywords: ["phpunit", "assertions", "test-quality", "regression-guard"]
trigger-on: ["phpunit-exact-assertion", "phpunit-query-count", "phpunit-output-assertion"]
---

## Make regression guards exact, and pair an absence assertion with a presence one

An assertion that only proves "at least" or "it contains something" can pass for the wrong reason and then never fail. Two habits prevent it.

Prefer an exact count when guarding a query-count fix. `self::assertCount(1, $domainQueries)` over a filter of `DB::connection('laravel')->getQueryLog()` proves the eager load happened; the same test written as `assertLessThan(2, ...)` or a truthiness check would also pass with zero queries logged — for instance if the log silently captured a different connection.

When asserting something is *absent* from output, add a sibling case asserting it is *present*, so a broken capture cannot make both vacuous: `->doesntExpectOutputToContain('re-derived')` on the unchanged input plus `->expectsOutputToContain('re-derived')` on the changed one. The passing positive case is the proof that the output pipeline works; without it, the negative case is indistinguishable from an assertion that never looks at anything.

The same reasoning applies to the test-first red step: if you did not observe the new assertion fail against the old behaviour, cite the exactness of the assertion (equality, count, string presence) as the reason it discriminates — do not simply assume it does.
