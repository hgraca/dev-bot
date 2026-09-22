---
date: 2026-09-22
keywords: ["git", "test-red-ability", "regression-test", "git-stash", "git-checkout"]
trigger-on: ["regression-test-pins-behaviour", "prove-test-fails-before-fix"]
---

## Prove a regression test can fail by reverting only the source, never the test

A new test that passes proves nothing unless it would have failed before the fix, and "absence" assertions are the worst offenders — a test asserting a deleted row is *not* listed passes happily if the query over-excludes every row. The mechanical proof is to revert the source while keeping the new tests: for an uncommitted fix, `git stash push -- <src paths>` (name the source paths so the test files stay in the working tree), run, then `git stash pop`; for an already-committed fix, `git checkout <fix-sha>~1 -- <src paths>` to restore the pre-fix source, run, then `git checkout <fix-sha> -- <src paths>`. Pair the assertion with a positive control — the row that *should* still come back — so over-exclusion cannot pass either. Two cautions learned the hard way: revert *every* file the fix touched, because reverting a renamed symbol on its own yields a fatal error rather than a red test; and when part of the fix is already committed and part is still in the working tree, save the uncommitted part as a patch first (`git diff -- <paths> > /tmp/fix.patch`) and `git apply` it back afterwards, since checking files out would otherwise silently discard it.
