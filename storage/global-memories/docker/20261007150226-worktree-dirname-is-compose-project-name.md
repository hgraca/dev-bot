---
date: 2026-10-07
keywords: ["docker", "compose", "worktree", "PROJECT_NAME"]
aliases: ["compose project name collision", "git worktree container clash", "PROJECT_NAME=dirname", "worktree container name"]
trigger-on: ["compose-project-name-worktree", "git-worktree-compose-up"]
---

## A worktree's compose project name is its directory basename, so same-named worktrees across repos collide

In the get-e dev-tools layout the `Makefile` sets `PROJECT_NAME := $(basename $(CURDIR))` when `_IS_WORKTREE=1` and `.docker/compose.dev.yml` declares `name: ${PROJECT_NAME:-audit-log}`; because the worktree tool slugifies the branch into the worktree's directory name, two worktrees in **different** repositories that share a branch name resolve to the **same** compose project (`chore/update-message-bus` → dir `chore-update-message-bus` → project `chore-update-message-bus`), and the second `make up` attaches to / recreates the first project's containers, hijacking a sibling session's environment. Pick a branch whose slug is unique across concurrently-running worktrees, confirm ownership before starting with `docker inspect <slug>-app-1 --format '{{ index .Config.Labels "com.docker.compose.project.working_dir" }}'`, and keep the slug dot-free (compose project names reject dots, so a version like `deps/message-bus-0.17.22.0` is unusable as a worktree path).
