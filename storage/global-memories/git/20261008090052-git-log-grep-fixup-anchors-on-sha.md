---
date: 2026-10-08
keywords: ["git", "fixup", "grep", "git-log", "autosquash"]
aliases: ["count fixup commits", "squash range"]
---

## Anchoring a grep on `git log --oneline` output tests the SHA, not the subject

`git log --oneline | grep -E '^(fixup|squash|amend)!'` never matches: the `^` anchor lands on the abbreviated SHA that starts every line, not the subject, so the filter silently returns nothing (a false "0 fixup commits"). Use git's own subject filter — `git log --oneline --grep='^fixup!'` (or `-E --grep='^(fixup|squash|amend)!'`) — or post-filter with a SHA-aware pattern when you already have the range: `git log --oneline origin/main..HEAD | grep -cE '^[0-9a-f]+ (fixup|squash|amend)!'`.
