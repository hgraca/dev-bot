---
date: 2026-09-26
keywords: ["docker", "docker-compose", "fault-isolation"]
trigger-on: ["compose-up-unit-failure"]
---

## `docker compose up` fails as a unit when any service cannot be prepared

Compose resolves and prepares every service in the project before starting any of them, so one service with an unpullable image or a broken `build:` context aborts the whole command and **no** container starts — the healthy ones included. `docker compose config` behaves the same way, rejecting the file outright (e.g. on a duplicate service key or a duplicate `container_name`). Separate containers therefore do not by themselves give fault isolation: if a failure in one service must not stop the others, bring them up individually (`docker compose up -d --no-deps <svc>`) or split them into separate compose files or projects. The mirror-image trap: a missing host path in a bind mount is silently created as an empty directory rather than failing, so a typo in a volume source looks like success.
