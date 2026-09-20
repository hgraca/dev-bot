---
date: 2026-09-14
keywords: ["docker", "docker-compose", "gpu", "docker-desktop"]
trigger-on: ["compose-gpu-device-reservation", "docker-desktop-gpu-passthrough"]
---

## A `devices: [gpu]` reservation fails the whole `docker compose up` where passthrough is unavailable

Requesting a GPU in compose (`deploy.resources.reservations.devices: [{capabilities: [gpu]}]`) does not degrade gracefully. On a host whose daemon cannot provide a GPU — Docker Desktop on macOS/Windows always — `docker compose up` fails outright, and under `set -e` that aborts the whole caller before anything else runs: nothing starts at all.

Gate such an overlay on a live capability probe, never on a persisted flag alone. A flag can be stale, or recorded from a host-only probe taken while the daemon was down. On macOS/Windows passthrough is never available, so requiring the live probe makes an over-eager flag degrade to "starts without GPU" instead of "does not start".
