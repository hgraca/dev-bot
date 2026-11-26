---
date: 2026-11-25
keywords: ["devbot", "codebase-memory", "docker", "recreate", "gateway"]
trigger-on: ["codebase-memory-gateway-wedged", "devbot-up-gateway-recovery", "cbm-daemon-could-not-start"]
supersedes: ["devbot/20260917172100-bare-devbot-runs-up-sh-before-the-harness.md"]
---

## `devbot up` now heals a wedged codebase-memory gateway, and `tmpfs: /tmp` is NOT the fix

A gateway container can exit 1 within seconds of starting (`codebase-memory-mcp: CBM daemon could not start within 30000 ms`) and then nothing listens on 18504, so every harness reports the server failed with ECONNREFUSED — while `bin/up.sh`'s `docker compose up -d --no-recreate` keeps restarting the same bad container. Since ARC-1102 the module's own `up.sh` recovers: it passes `CONTAINER_NAME` as the shared wait helper's fourth argument so an exited container fails fast instead of burning the 30-second retry budget, then force-recreates it **at most once per run** (`_GATEWAY_RECREATED` records the attempt, so a repo-mount reconciliation that already recreated it is reported and re-checked rather than recreated twice). The heal acts only on a definite `{{.State.Running}}` == `false` — an inspect that fails says nothing, matching the helper's own rule — and a recreate that does not help now warns and points at the `devbot-codebase-memory-store` volume as the next thing to check (an image, entrypoint or config failure looks identical, so the volume is a diagnostic, not a diagnosis).

The **negative result matters as much**: `tmpfs: /tmp` was proposed to prevent the wedge (the server's private daemon keeps socket/cohort locks in `/tmp/cbm-daemon-<uid>`, which lives in the writable layer and survives `docker stop`/`docker start`) and was **falsified by a control experiment** — a throwaway container from the same image, with a fresh store volume and no tmpfs, survived a stop/start with MCP answering 200 on both passes. The wedge therefore needs something a probe container does not have (the real store, the `$HOME` read-only bind mount, and, per the failing container's log, open SSE client sessions at stop time — the shutdown carried `ERROR: ASGI callable returned without completing response` twice). Prevention remains unsolved and upstream; do not re-propose tmpfs without reproducing the wedge on a container that has served real traffic.
