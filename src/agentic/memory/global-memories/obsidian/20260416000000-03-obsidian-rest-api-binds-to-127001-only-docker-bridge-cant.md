---
date: 2026-04-16
keywords: ["obsidian", "docker"]
---

## Obsidian REST API binds to `127.0.0.1` only — Docker bridge can't reach it

The Obsidian Local REST API plugin listens on `127.0.0.1:27124` (loopback only), not `0.0.0.0`. Docker containers on the default bridge network reach the host via `172.17.0.1` (Docker bridge gateway), so connection is refused. Fix on Linux: `--network host` in the `docker run` command so the container shares the host's network namespace. On macOS: Docker Desktop transparently maps `host.docker.internal` to the host loopback, so the default bridge works.
