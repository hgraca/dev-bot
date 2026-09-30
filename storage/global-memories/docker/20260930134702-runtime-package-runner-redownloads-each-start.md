---
date: 2026-09-30
keywords: ["docker", "uv", "uvx", "npx", "container-startup"]
trigger-on: ["docker-runtime-package-runner", "docker-uvx-startup-cost"]
---

## A container whose command is a package runner re-downloads deps on every start

Running `uvx <pkg>@<ver>` (or `npx -y <pkg>`) from a bare runtime image makes
**every container start** resolve, download and install the package. Measured
here: an OpenSearch MCP sidecar on `ghcr.io/astral-sh/uv:...` pulled 69 packages
per boot — a ~47% CPU burst and tens of MB of traffic — while every other
container in the same project started in milliseconds because their Dockerfile
baked the dependencies at build time.

Two fixes, in order of preference:

- **Bake it.** Add a Dockerfile that installs the package (`uv pip install --system "<pkg>@<ver>"`, `npm install -g "<pkg>@<ver>"`) and drop the runner from the command. Start-up becomes a plain exec. This is what a first-party sidecar in the same project already did.
- **Mount a cache.** Keep the generic runner, but point it at a shared host directory — `UV_CACHE_DIR=/var/cache/uv` bind-mounted from a dir created as the host user, or `npm_config_cache`. The install then resolves from cache instead of the network. `uv`'s cache is content-addressed, so one directory can serve several containers safely.

Check the `command:`/entrypoint of every container you add: if it is a package
runner rather than a fixed binary, it is paying this cost on every start. Note
the cache path is written by the container (usually root), so it lands
root-owned on the host — fine for a disposable cache, awkward to clean.
