---
date: 2026-10-26
keywords: ["docker", "pnpm", "inotify", "vite", "home"]
aliases: ["ENOSPC file watchers", "pnpm store inside project", ".pnpm-store"]
trigger-on: ["dockerfile-node-image", "vite-dev-container"]
---

## An unwritable HOME puts pnpm's store inside the project and kills the dev server

When a container runs as an arbitrary numeric UID, `/root` is not writable, so pnpm falls back to `<project>/.pnpm-store`. Vite then watches the whole bind-mounted project, including that content-addressable cache with hundreds of thousands of files, and dies with `Error: ENOSPC: System limit for number of file watchers reached` — after the server reports ready, so it looks like a routing/502 problem. Set `ENV HOME=/home/node` (or any writable path) and `chown -R ${UID}:${GID}` it alongside the app; the store leaves the project and the watcher count collapses. Watch the log for `ENOSPC` before suspecting Traefik.
