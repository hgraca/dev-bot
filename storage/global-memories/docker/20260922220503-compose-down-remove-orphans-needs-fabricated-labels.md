---
date: 2026-09-22
keywords: ["docker", "docker-compose", "remove-orphans", "container labels"]
trigger-on: ["compose-orphan-collection", "docker-run-container-not-collected-by-compose-down"]
---

## `compose down --remove-orphans` collects a hand-`docker run` container only with a fabricated label set

A container started by `docker run` (not by compose) carries no `com.docker.compose.*` labels, so `docker compose down --remove-orphans` never sees it — it is not a member of the project, whatever its image. To make compose collect such a container you must fabricate the labels on the `docker run`, and bisecting the set on Docker 29.8.1 / compose 5.5.1 showed the obvious pair is not enough: `project` + `service` alone are ignored, and the decisive label is `com.docker.compose.config-hash`. A set that does work: `config-hash` (any non-empty value — compose treats it as a stale config), `container-number`, `depends_on`, `image` (the image ID), `oneoff=False`, `project`, `project.config_files` (a real compose path), `project.working_dir`, `service`, `version`. Two further traps: if the fabricated `service` name IS defined in the referenced compose file the container is not an orphan and is never collected (only an *undefined* service is), and either way the container then appears in `docker compose ps` for that project as a service no file declares.

Prefer a tool-owned label plus an explicit reap — `docker ps -aq --filter label=<owner>.<thing>=<name> | xargs -r docker rm -f` — over fabricating compose internals. The label filter is documented, stable across compose versions, and scoped to your own containers, whereas an `ancestor=<image>` filter also catches a container the user started by hand. Use `-a` in the reap: a container stranded on a dead stdin is usually still running, but one that exited without `--rm` firing is equally garbage.
