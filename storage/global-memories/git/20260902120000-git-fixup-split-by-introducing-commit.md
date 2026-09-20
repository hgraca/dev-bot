---
date: 2026-09-02
keywords: ["git", "fixup", "autosquash", "introducing-commit"]
trigger-on: ["git-fixup-split-by-introducing-commit"]
---

## Split fixups by the commit that introduced each file — a bundled fixup targeting one commit conflicts when its files came from different commits

When a review fix touches several files that entered the branch in DIFFERENT commits (e.g. a handler added in commit A plus its caller added later in commit B), bundling them into one `git commit --fixup=<A>` and autosquashing conflicts: the hunk for B's file can't apply at A's position in the replay ("file deleted in HEAD / modified by them"), aborting the rebase mid-way. Target each file's own introducing commit (find it with `git log --oneline -- <file>`): one fixup per commit a file belongs to, then autosquash. Also: run the full gate (make test) BEFORE autosquashing — the cs-fixer/Rector steps modify the working tree during the run, and an uncommitted change blocks `git rebase` with "cannot rebase: you have unstaged changes".
