---
date: 2026-10-30
keywords: ["devbot", "worktree", "cleanup", "root-owned", "hosts"]
aliases: ["stale worktree sweep", "worktree teardown leftovers"]
trigger-on: ["devbot-worktree-cleanup", "worktree-remove"]
---

## Worktree cleanup leaves root-owned files and can race a live session

`worktree.sh remove` (and `git worktree remove`) deletes the checkout, but container-run builds leave root-owned files behind — `vendor/` written by an in-container composer install and `storage/cache/static_analysis` written by PHPStan/Rector — so a follow-up sweep dies with `Permission denied` and the directory survives partially emptied. Check with `find <dir> -user root | wc -l` and finish with `sudo find <dir> -depth -delete`; there is no unprivileged path once a container has written into the tree. Two related traps: a bulk removal loop can report `FATAL: no worktree is registered for '<branch>'` on every entry because a concurrent devbot session already removed them (new `chore/dev-tools-*` worktrees appearing is the tell) — verify the directories afterwards instead of trusting the loop; and per-worktree `/etc/hosts` entries can only be handed to the human, because the harness denies agent writes outside the workspace even though the file itself is world-writable.
