---
date: 2026-11-26
keywords: ["git", "git-add", "gitignore", "tracked-file"]
---

## `git add -u` updates a tracked path that an ignore rule covers

A tracked file can still match an ignore rule — `.agents/memory` in `.git/info/exclude`, a fixture's
`.agents/**`, or a repository's blanket `.gitignore`. `git add <path>` refuses with
`The following paths are ignored by one of your .gitignore files` even though the file is tracked,
and a `git add && git commit` chain stops there.

`git add -u <path>` stages the change without force. Never reach for `-f`: the file is already
tracked, so only the ignore check is wrong. Verify the result with `git diff --cached` and commit in
a separate step.
