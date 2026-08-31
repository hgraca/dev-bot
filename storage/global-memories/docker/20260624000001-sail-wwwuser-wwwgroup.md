---
date: 2026-06-24
keywords: ["docker", "sail", "build-args", "laravel"]
trigger-on: ["sail-setup", "docker-compose-build", "WWWUSER"]
---

## Laravel Sail build fails without WWWUSER and WWWGROUP env vars

Sail's Dockerfile uses `ARG WWWGROUP` and `ARG WWWUSER` passed as build args from compose.yaml (`${WWWGROUP}` / `${WWWUSER}`). When these env vars are not set in the shell, Docker defaults them to empty strings, causing `groupadd --force -g $WWWGROUP sail` to fail with exit code 3. Fix: export them before building — `export WWWUSER=$(id -u) WWWGROUP=$(id -g) && docker compose up -d`.
