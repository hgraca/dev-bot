---
date: 2026-10-18
keywords: ["git", "shared-checkout", "history-rewrite", "head-drift"]
aliases: ["concurrent commit during squash", "stale HEAD rewrite"]
trigger-on: ["git-history-rewrite", "shared-checkout"]
---

## Re-read HEAD immediately before a history rewrite in a shared checkout

A rebase that aborts on a dirty tree (dry-run, failed plan) does not freeze the branch: another session can commit onto it between that check and your rewrite. Re-read `git rev-parse HEAD` immediately before `rebase`/`update-ref` and assert it still equals the SHA the plan was built against. Observed in dev-bot on 2026-10-18: a plumbing squash (`commit-tree` with the pre-check base plus `update-ref`) silently collapsed a foreign commit that had landed on top of the three commits being squashed. The fix was restoring the branch from the recorded old SHA, then running a normal `rebase -i --autosquash`, which keeps the foreign commit as its own pick — its SHA necessarily changes, so verify its files survive and tell its owner.
