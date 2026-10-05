---
date: 2026-10-06
keywords: ["docker", "docker-compose", "worktree", "ports"]
trigger-on: ["docker-compose-worktree-isolation", "compose-host-port-collision"]
---

## A compose project name scopes names and volumes, not published host ports

Per-worktree isolation of a compose dev environment usually relies on the project name defaulting to the working directory: each worktree gets its own container, network, and volume names, so parallel sessions do not collide. That isolation does **not** extend to published host ports — port bindings are host-global. Two worktrees that each `docker compose up` a service with a fixed mapping (e.g. `127.0.0.1:18434:...`) fail the second start with `bind: address already in use`, so a worktree-scoped project name does not make a fixed-port service safe to run concurrently. To run host-port-bound services per worktree, scope the ports too (per-project overrides or environment), or avoid starting them per worktree and share one instance.
