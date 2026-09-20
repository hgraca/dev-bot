---
date: 2026-08-31
keywords: ["docker", "docker-compose", "project-name", "container"]
trigger-on: ["docker-compose-project-name-container"]
---

## Running `docker compose up` outside the project Makefile creates a differently-named container

A project whose Makefile invokes compose with `PROJECT_NAME=<x>` (see the dev-tools `Makefile` pattern: `ENV_VARS=env ... PROJECT_NAME=${PROJECT_NAME} docker compose ...`) creates containers named `<project-name>-app-1`. Running `docker compose -f .docker/compose.dev.yml up -d app` directly, **without** that env var, makes compose fall back to the compose file/directory project name and creates a _second_ container (`<dir>-api-app-1` or similar) — while the Makefile's `EXEC` still targets `<project-name>-app-1`, so `make t` etc. fail with "container ... is not running". Fix: remove the wrongly-named container and start via the Makefile path — `PROJECT_NAME=<name> docker compose -f .docker/compose.dev.yml up -d app` (or simply `make up`).
