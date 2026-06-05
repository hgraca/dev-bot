---
date: 2026-05-07
keywords: ["bun", "test"]
---

## Refactor regression-proof technique: `git stash` → re-run failing tests → `git stash pop`

When a refactor lands in a repo whose test suite already has pre-existing failures, you can't just look at "tests pass" — you need to prove your change introduced no new failures. Technique: (1) stage all your refactor changes; (2) `git stash` to set the working tree back to the pre-refactor baseline; (3) run the SAME test command (`bun test tests/plugins/`); (4) record pass/fail count; (5) `git stash pop` to restore your changes; (6) re-run the same test command; (7) compare counts. If both runs show identical pass/fail (e.g. 213/61 → 213/61), the refactor is provably regression-free even when the suite isn't all-green. Validated on the agent-communication rename (commit `2d902ad`): pre-existing baseline of 213/61 was unchanged before and after rename, allowing confident push despite 61 unrelated failures. Cheaper than chasing every pre-existing failure to green before shipping. Cross-ref [[gotchas]] for the cross-file test pollution that produced the 61 baseline failures, and the make-tests SKILL's tmpdir-isolation MUST NOT rule.
