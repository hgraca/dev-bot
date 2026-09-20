---
date: 2026-09-14
keywords: ["docker", "docker-compose", "container_name", "orphan"]
trigger-on: ["compose-project-rename", "fixed-container-name-conflict"]
---

## Renaming a compose project permanently wedges `up` on a fixed `container_name`

`docker compose down --remove-orphans` only touches containers belonging to the **same** compose project, so a container created under an older project name (after a `name:` change) is never removed — it is not a member of the new project. Because services commonly declare a fixed `container_name`, every later `docker compose up` for the new project then fails with `Conflict. The container name "/x" is already in use by container "..."`. The failure is permanent and survives every down/up cycle, and under `set -e` it aborts the whole caller, so the visible symptom usually looks unrelated to docker.

Fix: reclaim by name before `up`. List candidates with `docker ps -a --filter 'name=<prefix>' --format '{{.ID}}|{{.Names}}|{{.Label "com.docker.compose.project"}}'`, then `docker rm -f` every row whose project label is not the current project (an empty label means a manual `docker run`). Keep every container name under one stable prefix so the reclaim is a single filter, pin every compose file to the same `name:` so compose never targets two projects, and guard that prefix with a test.
