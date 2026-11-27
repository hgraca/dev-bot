---
date: 2026-11-27
keywords: ["git", "reset --soft", "rebase", "origin/main"]
aliases: ["reset soft reverts main", "branch base moved", "squash on stale base"]
---

## `git reset --soft origin/main` on a stale branch reverts main's new commits

Squashing a feature branch into one commit with `git reset --soft origin/main` is only safe while `origin/main` is still the branch's parent. If main advanced since the branch was cut, the index keeps the branch's tree — which predates those commits — so the new commit's diff against main _deletes_ every file main gained. Symptom: a "one-commit" squash that shows 70 files and `create mode` lines for other people's work.

`git diff --stat origin/main HEAD` does not reveal it before the commit: it compares the branch tree with main and _looks_ like your change. Check the parent instead — `git rev-parse HEAD^` must equal `git rev-parse origin/main` — or read the file count in `git show --stat` after committing.

Recovery: the pre-reset commit is in the reflog (`git reset --soft HEAD@{1}`), then rebase onto the current main with signing off if needed:

```bash
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false git rebase origin/main
```

`-c commit.gpgsign=false` on the rebase command itself does not reach the sequencer's commits; the `GIT_CONFIG_*` environment form does.
