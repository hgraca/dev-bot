---
date: 2026-11-04
keywords: ["docker", "bind-mount", "worktree", "compose"]
---

# compose auto-creates a missing bind-mount source as a directory

A fresh git worktree holds only tracked files, so gitignored local overrides such as `.docker/php.overrides.ini` and `.docker/xdebug.overrides.ini` are absent. `docker compose run` does not fail with "missing source": it creates the path as an empty **directory**, then the container dies with `not a directory: Are you trying to mount a directory onto a file (or vice-versa)?`. The message names the mount, not the cause, and the auto-created directory is root-owned, so a later `cp` of the `.dist` file silently targets a directory.

Restore the overrides before the first compose run in a worktree — copy each `*.overrides.ini.dist` to its target, and `rmdir` the stray directory first if a previous attempt created one. Worth checking both `.docker/` and `.docker/php/`, since projects differ on where they keep them.
