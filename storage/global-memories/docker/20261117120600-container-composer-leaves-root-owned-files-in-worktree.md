---
date: 2026-11-17
keywords: ["docker", "composer", "git-worktree", "permissions"]
aliases: ["git worktree remove permission denied", "root owned vendor", "container composer as root"]
trigger-on: ["containerized-composer", "worktree-cleanup"]
---

## Running composer in a container against a mounted worktree leaves root-owned files that block `git worktree remove`

`docker run --rm -v "$PWD:/app" -w /app composer:2 composer update ...` writes `vendor/` (and anything else the run creates, e.g. a plugin's `storage/`) as **root**, because the image runs as root and the bind mount carries the container uid through. The checkout still looks clean — `git status --porcelain` is empty, those paths are gitignored — so `git worktree remove` deregisters the worktree and then fails on the delete:

```
error: failed to delete '<path>': Permission denied
```

leaving a ~200 MB orphan directory with a dangling `.git` file, outside git's control and only removable by root. Passing `-u "$(id -u):$(id -g)"` to the container avoids it entirely, at the cost of needing a writable HOME/composer cache inside the container — usually worth it for any run that touches a directory you intend to delete afterwards.
