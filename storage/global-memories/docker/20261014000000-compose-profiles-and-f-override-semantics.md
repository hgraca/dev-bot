---
date: 2026-10-14
keywords: ["docker", "docker-compose", "compose-profiles", "compose-override"]
---

## Docker Compose `-f` disables override auto-load; named services bypass profiles

Verified on Docker Compose v5.6.0: passing `-f <file>` disables auto-loading of override files (`compose.override.yml` and friends) — overrides only merge when passed as an explicit second `-f`, or when no `-f` is given and the default-named file is used, so a Makefile that hardcodes `-f compose.dev.yml` silently ignores any override file dropped next to it. Separately, a service under `profiles: ["x"]` is skipped by a bare `up`/`up -d` (the opt-in pattern), but naming it explicitly (`up -d <svc>`, `run <svc>`, `stop <svc>`) still works without `--profile` — only the bare all-services `up` honours the profile filter. To make a service opt-in while keeping an on-demand target, add `profiles` to the base compose file and use `docker compose up -d <svc>` (or `--profile x up -d <svc>`) in the target; do not rely on an override file when the Makefile already passes `-f`.
