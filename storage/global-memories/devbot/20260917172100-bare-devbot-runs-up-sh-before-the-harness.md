---
date: 2026-09-17
keywords: ["devbot", "up.sh", "harness start", "no-recreate", "container recovery"]
trigger-on: ["devbot-up", "mcp-gateway-wedged", "devbot-start-order"]
---

## A bare `devbot` runs bin/up.sh before the harness — and `--no-recreate` never heals a wedged container

`bin/devbot`'s harness command brings the services up **first** (its own help text: "Starts the configured harness (opencode or claudecode) after running devbot up"; the call sits in `cmd_harness`). Consequence: a dev-bot-managed service can never be down when opencode starts — restarting the harness resurrects it. Reproducing any "dependency unavailable at harness start" failure therefore requires a dependency dev-bot does not manage: a sibling project's compose service (e.g. the shared dev DB `shared-db-1`, compose project `shared` from `core/vendor/get-e/dev-tools`) or a config pointer to a dead endpoint. A test built on stopping a dev-bot container silently proves nothing.

Second half of the trap: `bin/up.sh` runs `docker compose up -d --no-recreate`, so a container whose **own state** has gone bad is never repaired by `devbot up`. Observed with the codebase-memory gateway: its stdio child aborted with `CBM daemon could not start within 30000 ms` (poisoned per-container state in its writable layer) while the image, binary, pinned spec and mounts were all verified healthy, and a fresh container with identical configuration started fine. Recovery is `docker rm -f <container>` followed by `devbot up`, which creates it fresh. Note the container's own `/tmp` persists across `docker stop`/`docker start`, so a restart of the same container reproduces the wedge.
