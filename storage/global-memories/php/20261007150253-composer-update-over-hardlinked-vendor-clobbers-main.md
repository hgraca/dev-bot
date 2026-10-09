---
date: 2026-10-07
keywords: ["php", "composer", "worktree", "hardlink", "vendor"]
aliases: ["linked vendor clobbered by composer", "worktree vendor hard-link"]
trigger-on: ["composer-in-git-worktree", "worktree-linked-vendor"]
---

## A hard-linked `vendor/` is unsafe to run composer against in a git worktree

Worktree tooling that hard-links the main checkout's `vendor/` into a fresh worktree makes a
`composer update`/`require` there mutate the main checkout too: composer regenerates
`vendor/composer/autoload_*`, `installed.json` and `installed.php` with in-place writes
(truncate + write), and a hard link shares the inode — so the main checkout's autoloader ends up
pointing at the worktree's package versions while its lock still pins the old ones. Removing a
package directory in the worktree is safe (it only drops that directory entry); the generated
files are not. Create the worktree with the tool's no-link option (`--no-link` for `worktree.sh`)
and run a fresh `composer install` inside it; treat hard-linked dependency directories as
read-only.
