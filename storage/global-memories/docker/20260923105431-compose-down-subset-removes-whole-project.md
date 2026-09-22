---
date: 2026-09-23
keywords: ["docker", "docker-compose", "remove-orphans", "compose-project"]
trigger-on: ["docker-compose-shared-project", "compose-down-remove-orphans"]
---

## `docker compose down --remove-orphans` acts on the whole PROJECT, not the `-f` set

`docker compose down` only sees the files passed with `-f`, but `--remove-orphans` then removes **every container in that compose project which the given files do not declare** — so a `down` invoked with a subset of a project's compose files tears down the rest of the project too. The `-f` list scopes which services are stopped and removed directly, not the blast radius. This is easy to get wrong when several independent concerns share one compose project (all dev-bot modules declare `name: devbot`, so their containers are a single project): a command meant to stop "my subset" silently removes a sibling's containers. Two consequences: if the project is shared machine-wide, a subset-scoped `down` breaks whoever else was using the other containers; conversely, a subset `down` is the only way to collect containers whose compose file sits outside the discovery path — they look like orphans and get removed. Decide deliberately which of the two you want, and never make a subset `down` reachable while another consumer may be live.
