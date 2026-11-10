---
date: 2026-11-10
keywords: ["review", "pull request", "fixup", "squash"]
aliases: ["review-before-pr", "amend before opening the PR"]
see: ["ADRs/20261106163656-review-loop-gates-on-green-ci.md"]
supersedes: ["learnings/20261023171442-fixups-cannot-fold-after-push.md"]
---

## Local review, its fixes and the squash happen before the pull request is opened

Stakeholder decision (2026-11-09). The assignment-end review loop now runs before the pull request exists, not after the workflow opened it. Under the Worktrees workflow the local review, its fixes recorded as fixups, and the interactive `git rebase -i --autosquash origin/<default>` that folds them into their targets all happen on the branch while it is still local; the plan-and-approval gate of `devbot:git-fixup-commits` still applies, and the pushed branch carries no `fixup!` commits. Trunk is untouched: its commits are already on the default branch, are never rewritten, and a correction there is a normal follow-up commit. Feedback that arrives after the pull request exists stays in `devbot:gh-review-loop` with fixups, squashed before the merge. This reverses the earlier "fixups cannot fold after push, so use a normal follow-up commit instead" guidance: doing the fold first keeps the local window open, so the conflict that note described no longer arises.
