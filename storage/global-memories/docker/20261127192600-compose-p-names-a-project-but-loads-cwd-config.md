---
date: 2026-11-27
keywords: ["docker", "compose", "labels", "teardown"]
aliases: ["compose down wrong project", "orphaned worktree containers", "compose project label"]
trigger-on: ["docker-compose-project-scoped-teardown"]
---

## `docker compose -p` names a project, it does not load that project's configuration

`docker compose -p <name> down` does not read the files that project was created from: it loads whichever compose file the current directory resolves to, so run from a checkout that has a compose file of its own it validates — and can fail on — the wrong stack's configuration, and once the directory holding the original file is deleted there is nothing left to load. Remove a project's resources without its file by going through the labels compose stamps on them — `docker ps -aq --filter label=com.docker.compose.project=<name>`, and the same filter on `docker volume ls` and `docker network ls` — which is what `down` does internally and needs neither a file nor a working directory. Ownership is only provable per container: containers carry both `com.docker.compose.project` and `com.docker.compose.project.working_dir`, while volumes and networks carry the project name alone. Two checkouts of one repository can produce the same project name (it is built from the directory basename), and a sibling whose containers are stopped leaves nothing to tell its volumes from yours — so match containers on both labels, and treat project-labelled volumes and networks as report-only.
