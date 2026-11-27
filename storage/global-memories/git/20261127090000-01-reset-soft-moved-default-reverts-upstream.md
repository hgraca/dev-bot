---
date: 2026-11-27
keywords: ["git", "reset --soft", "origin/main", "squash", "upstream"]
---

## A squash must reset to the branch's own base, never to the default branch's current tip

Squashing a feature branch with `git reset --soft origin/main` is only safe while `origin/main` still
points at the commit the branch was cut from. If upstream landed commits after the branch started — the
normal case for a branch older than a few hours — that reset stages the _absence_ of those commits too:
the single commit that follows silently reverts every upstream change, and the tree no longer matches
the one that was reviewed and tested.

The failure is quiet: the reset succeeds, the commit succeeds, and only a tree comparison reveals it
(`git rev-parse HEAD^{tree}` before and after). The safe forms are `git reset --soft <branch-base>`
where `<branch-base>` is `git rev-parse <first-branch-commit>^`, or an autosquash rebase onto a base
that is an ancestor of every commit being rewritten. Verify with the tree hash, not with the log.
