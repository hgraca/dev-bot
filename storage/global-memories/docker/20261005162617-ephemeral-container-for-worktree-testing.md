---
date: 2026-10-05
keywords: ["docker", "docker-compose", "worktree", "container"]
trigger-on: ["docker-compose-worktree-bound-container"]
---

## Test a git worktree in an ephemeral container when the compose dev container is bound to another worktree

A docker-compose dev environment bind-mounts the working tree into the container, so it serves whichever checkout last ran the compose "up" — in a repo using git worktrees that may be a different worktree than the one you are editing, and if the compose `name:` is fixed, `docker compose ... exec`/`make` from your worktree either cannot find the container or silently runs against the other checkout. Do not take the shared environment over from a sibling session; run your commands in a one-off container from the same image instead, mounting your worktree at the app path and joining the compose network so it reuses the already-running db/redis/broker services:

```bash
docker run --rm --user "$(id -u):$(id -g)" \
  -v "$WORKTREE:/app" -w /app \
  --network <compose-project>_default \
  <image> bash -lc 'composer install && vendor/bin/phpunit'
```

The fresh worktree has no `vendor/`, so install dependencies once inside it first. Find the network with `docker network ls` and the image with `docker compose ... ps` (or `docker inspect` of the running container, which also reveals which worktree it is actually bound to).
