---
date: 2026-10-26
keywords: ["shell", "makefile", "worktree", "compose", "traefik"]
aliases: ["PROJECT_NAME collision", "same worktree dir two repos", "container name clash"]
trigger-on: ["makefile-worktree-identity"]
---

## A worktree whose compose identity is only its directory name collides across repositories

Deriving a linked worktree's `PROJECT_NAME` from the directory alone gives the same value for the same branch checked out as a worktree of two different repos (`feat-x-app-1` for both) — so compose reuses the container, `docker exec <name>` reaches whichever started first, and the Traefik router names collide too. Qualify it with the main checkout's directory: `<worktree-dir>-<project>`. The browser host must come from a separate variable (`WORKTREE_PREFIX` + the project's host base), otherwise the hostname grows the same suffix and stops matching the certificate.
