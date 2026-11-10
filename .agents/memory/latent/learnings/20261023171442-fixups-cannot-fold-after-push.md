---
date: 2026-10-23
keywords: ["fixup", "force-push", "autosquash", "pull-request"]
aliases: ["fixup after push", "squash review fixes", "cannot autosquash pushed branch"]
superseded_by: ["PDRs/20261110095143-local-review-before-opening-the-pull-request.md"]
---

# Fixups on an already-pushed branch cannot be folded without a force-push

> **Superseded by** `PDRs/20261110095143-local-review-before-opening-the-pull-request.md` (2026-11-10).

`devbot:git-fixup-commits` requires `--fixup=<sha>` for a correction on a feature branch, but folding those fixups needs `git rebase --autosquash`, which rewrites commits already on the remote. `devbot:git-commits` forbids rewriting shared history without explicit approval, and the guards tool blocks a force-push outright (see `ADRs/20261020112642-02-guards-git-force-push-token-scan.md`), so the two rules collide the moment review comments arrive after the branch is pushed.

## What to do

Record the correction as a normal follow-up commit with the same Problems/Solutions body, and let the repository's squash-merge collapse the PR into one commit. Use `--fixup` only inside the window between the first commit and the first push — after that it buys nothing that squash-merge does not already give.

## Why it bites

The PR review loop is exactly when corrections appear, so the "branch still local" window is usually already closed by then. A `--fixup` created at that point either forces a history rewrite or strands an unfoldable `fixup!` commit on the PR; squash-merge makes the follow-up commits invisible on the default branch, so nothing is lost by not using one there.
