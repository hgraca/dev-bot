---
date: 2026-10-23
keywords: ["php", "composer", "worktree", "insteadOf", "docker"]
aliases: ["composer update needs ssh in container", "bump vcs dependency without credentials", "docker compose run missing bind file"]
trigger-on: ["composer-bump-vcs-dependency", "worktree-composer-update"]
---

## Bumping a VCS-packaged composer dependency inside a worktree, without credentials or a stack

Composer resolves `{"type": "vcs", "url": "git@github.com:Org/pkg.git"}` by shelling out to git, so it needs
**git and an ssh client inside whichever container runs it** — many project dev images have neither, and a
fresh worktree has no `vendor/` to fall back on. Two ready-made routes:

- `docker compose run --rm --no-deps --entrypoint composer app …` fails on gitignored bind-mount sources
  (`.docker/*.ini`, `.env`) that only `make up` creates. Create empty placeholder files for every missing
  bind source in the compose config before running; no stack is needed.
- When the image has git but no ssh (or no credentials), map the VCS URLs onto local checkouts with a
  throwaway gitconfig and `GIT_CONFIG_GLOBAL`: `[url "/host-gete/<pkg>"] insteadOf = git@github.com:Org/<pkg>.git`
  (repeat per package, also for the `https://` form), mount the workspace read-only, and add
  `--ignore-platform-reqs` when the image's PHP differs. Composer still records the declared GitHub URL and
  commit SHA in the lock, so the diff is correct. Refresh stale local mirrors with `git fetch --tags` first —
  a mirror missing the latest tags silently makes an upgrade unresolvable.

Watch ownership: a compose service with `user: ${UID:-0}:${GID:-0}` and UID unset runs as root and leaves a
root-owned `vendor/`, after which a later `--user <uid>` composer run dies on
`copy(/app/vendor/composer/tmp-*.zip): Permission denied`. Run as root to finish, then chown the tree back.
