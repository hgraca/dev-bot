---
date: 2026-08-04
keywords: ["git", "ci", "diff", "branch", "merge-base"]
trigger-on: ["stale-branch-ci-failure", "three-dot-diff", "isolated-migrations-check"]
---

## Stale branch causes three-dot git diff to include unrelated changes in CI

When a feature branch is created from an outdated default branch (merge-base far behind origin/main), `git diff main...HEAD` in CI includes ALL changes between that old merge-base and HEAD — not just the branch's own changes. This is because three-dot syntax (`A...B`) diffs from the merge-base of A and B to B.

This causes false positives in CI checks that scan the diff for specific patterns (e.g. migration files). A branch with zero migrations can fail an "isolated migrations" check because the diff picks up migration files from main-branch commits that happened after the stale branch point.

**Fix:** Recreate the branch from the latest default branch and re-apply changes. Use `git diff origin/main...OLD_COMMIT -- <files>` to extract just the branch's actual changes as a clean patch, then `git checkout -b new-branch main && git apply <patch>`.
