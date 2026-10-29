---
date: 2026-10-29
keywords: ["devbot", "prose-contract", "bats", "module-ownership"]
trigger-on: ["devbot-prose-contract-test-placement"]
---

## Guard a prose rule in the module that owns it, not a sibling module's suite

When a rule lives in `src/agentic/<module>/`, its prose-contract test belongs in that module's own `tests/` suite. A test in a sibling module's file passes, but leaves the owning module with no local gate — and it makes one test file span two modules, so a future edit to the rule has no obvious place to add its assertion.

The precedent that misleads: `src/agentic/git/tests/fixup_commits_tests.bats` loads fixture paths for other modules (`CREATE_PR`, `WORKTREES`, `SOFTWARE_DEV`) and is the natural home for anything touching the squash hand-off. Those fixtures are for cross-file flows (fixup → squash → PR); a rule the github module alone states still goes in `src/agentic/github/tests/`. Scope assertions to the section that carries the rule with the file's own `section`/`subsection` helpers rather than whole-file `grep`, so a reworded-but-correct file passes and a deleted rule fails.
