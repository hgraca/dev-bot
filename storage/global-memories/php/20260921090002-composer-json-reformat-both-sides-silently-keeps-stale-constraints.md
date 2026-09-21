---
date: 2026-09-21
keywords: ["php", "composer", "merge-conflict", "rebase", "reformat"]
trigger-on: ["composer-json-merge", "rebase-conflict"]
---

## A composer.json reformatted on both sides makes the 3-way merge keep stale constraints silently

When a branch reformats `composer.json` (indent style, short arrays collapsed inline) while the target branch changes dependency constraints, git's line-based merge can take the branch's side for whole regions and silently reinstate the *branch's older* constraints — with no conflict marker anywhere. Observed immediately after rebasing onto a Laravel major upgrade: the auto-merged file still read `laravel/framework: ^12` while the target branch required `^13.0`, so the merge looked clean but would have downgraded the framework. Never trust an auto-merged `composer.json`. After any rebase or merge, diff the file against the target branch and assert that the key constraints (`php`, framework, and every shared package) match the target's values, not the branch's. The reliable repair is to rebuild the file from `git show <target>:composer.json` and re-apply only the branch's intended additions, rather than resolving the conflict textually.
