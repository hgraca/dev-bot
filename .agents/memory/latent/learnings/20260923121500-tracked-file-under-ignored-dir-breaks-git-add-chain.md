---
date: 2026-09-23
keywords: ["git-add", "gitignore", "test-project-fixture", "shell-chaining"]
---

# A tracked file under an ignored directory breaks a `git add && …` chain

The e2e fixture's vault files — `tests/test-project/.agents/memory/active/*.md` — **are tracked**, but `tests/test-project/.gitignore` line 18 ignores `.agents/**` (the fixture mimics a consumer project). Running `git add tests/test-project/.agents/memory/active/preemptive-skill-loading-list.md` prints `The following paths are ignored by one of your .gitignore files: tests/test-project/.agents/memory` and **exits non-zero**, so any `cmd && git add <fixture> && git commit …` chain silently stops — while the tracked file _is_ still staged (verify with `git diff --cached`, which shows the insertion). `git check-ignore -v --no-index <file>` is the reliable probe: it reports the matching rule even when the file is already tracked, whereas a plain `git check-ignore` does not. Rule: never chain a commit behind a `git add` that touches these fixture paths; stage first, inspect `git diff --cached`, then commit as a separate step.
