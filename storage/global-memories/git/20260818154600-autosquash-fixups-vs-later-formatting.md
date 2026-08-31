---
date: 2026-08-18
keywords: ["git", "rebase", "autosquash", "fixup", "conflict"]
trigger-on: ["git-autosquash-rebase", "fixup-conflict-rebase"]
---

## Autosquash fixups authored against later formatting conflict before it replays

When a fixup is created on top of a formatting/style commit that touched the same file, `git rebase -i --autosquash` replays the fixup right after its target commit — BEFORE the style commit. If the fixup's diff context assumes the formatted file (e.g. prettier), it conflicts on that hunk. Resolve keeping the intended content; then `git rebase --continue` on a conflicted fixup opens the message editor — use `GIT_EDITOR=true GIT_SEQUENCE_EDITOR=: git rebase --continue`. If a subsequent style commit's changes were already absorbed by the conflict resolution, git drops it as empty; that is expected, not an error. Prove the rebase preserved content by comparing trees: `git rev-parse <old-head>^{tree}` vs `git rev-parse HEAD^{tree}` (identical = safe).
