---
date: 2026-09-23
keywords: ["git", "rebase", "autosquash", "range-diff"]
trigger-on: ["git-autosquash-base-check", "squash-content-verification"]
---

## Squash with the tight base, and verify content with `git range-diff` — not a diff hash

`git rebase -i --autosquash main` uses whatever `main` points at **right now**. In a shared clone where another session has pulled, `main` can advance mid-task (observed: local `main` moved from `1a46e832ca` to `3bcb13c84d` while a review round was in flight), so squashing fixups silently rebases the branch onto the newer base as well — a far wider rewrite than intended, pulling every new upstream commit in as an ancestor of your branch. Before the rebase, confirm the base has not moved (`git rev-parse main origin/main`) and prefer the tight base the fixup skill prescribes: `git rebase -i --autosquash <target-sha>^`, which limits the blast radius to the commits being folded.

Verifying the result: a changed tree hash between the pre- and post-squash tips does **not** prove content loss when the base moved, because the patch text — and therefore `git diff | git hash-object` — shifts with the surrounding context lines. Use `git range-diff <old-base>..<old-tip> <new-base>..<new-tip>` instead: the commit mapping prints `=` for commits replayed byte-identically, `!` for ones that changed (expected for the fixup target — the fixups folding in *is* the change), and `< -:` for commits folded away. Cross-check with `git diff <new-base> <new-tip> --stat`, which must list only the files the change actually touches, since the newer base commits are ancestors rather than diff content.
