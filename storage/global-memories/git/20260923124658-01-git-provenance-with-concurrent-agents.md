---
date: 2026-09-23
keywords: ["git", "provenance", "fixup", "concurrent-agents"]
trigger-on: ["git-provenance-check", "fixup-commit-traceability"]
---

## Verify provenance with `git log main..HEAD`, not `git status`

In a workspace where several agent sessions share one clone, `git status` showing only your edited files does NOT prove the other files are pre-existing: a branch can already contain commits from another session, and another session can commit onto your branch mid-task (observed: an unrelated `fix(logging): emit one critical log per uncaught exception` landed between a feature commit and its fixups while the task was still running). Before calling anything "pre-existing", run `git log --oneline main..HEAD` and compare it against your own commit list — in this session `git status` looked clean while four commits, and later one more, belonged to someone else, and a wrong "pre-existing" claim had to be retracted. Two related mechanics: stage by explicit path (never `git add -A`/`git add .`) so a concurrent session's working-tree edits cannot ride along; and note that `git commit --fixup=<sha>` writes the identical subject `fixup! <target subject>` for every fixup, so several fixups against one commit carry no per-item traceability — state which fixup answers which finding in the report instead of relying on the log.
