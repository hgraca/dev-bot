---
date: 2026-09-17
keywords: ["devbot", "datasources", "mcp", "docker", "networking", "toolbox"]
see: ["ADRs/20260914222815-share-machine-wide-mcp-servers-via-compose-gate-per-project.md", "ADRs/20260908213000-mcp-manifest-consolidation.md"]
---

## Run the datasources gateway on the host network, from a generated compose file

The `datasources` module (`src/agentic/datasources/`) serves project databases to agents through one shared MCP Toolbox container on `127.0.0.1:18510`. It follows ADR `20260914222815`: the server is remote (http), runs once per machine, and every harness connects to it rather than spawning its own copy. Four of its mechanics deviate from what that ADR assumed, and each was forced by an observed failure rather than by preference.

**Decision — the gateway joins the host network (`network_mode: host`), and the server binds `127.0.0.1`.** Databases on a development machine are normally published on the host's loopback, and a bridged container cannot reach those: `host.docker.internal` resolves to the bridge gateway (`172.17.0.1`), where a database published as `127.0.0.1:3306` is not listening. The failure is silent in the worst way — a reachability probe run on the host reports the database up while the container gets `connection refused`, so the datasource never activates. Sharing the host's network namespace makes the container's view identical to the probe's, which is what makes activation trustworthy. Binding loopback rather than `0.0.0.0` keeps the gateway off the LAN, and with no port mapping the container binds the host's `18510` directly.

**Decision — the compose file is generated into `storage/datasources/`, and the module brings it up and down.** Toolbox reads connection parameters from environment variables, so the gateway must receive a variable for every value a datasource references — and those names are dynamic, taken from `.devbot.global.jsonc` at run time. Compose cannot express "the whole environment", so the file must be rendered. Only variable NAMES are written; the values are interpolated by compose from the environment `devbot up` builds, so no credential reaches disk. Because the rendered file lives outside `src/`, `bin/up.sh` discovery does not see it, and `up.sh`/`down.sh` own its lifecycle.

**Decision — readiness is external; the container declares no healthcheck.** The toolbox image is distroless (no shell, no `python3`), so nothing can run a probe inside it. `up.sh` waits on a real MCP handshake over the network instead, reporting the gateway unavailable rather than failing the boot — the same substitute `signoz` uses. `restart: "no"` follows the other gateways: a dev-machine service should not return after a reboot without `devbot up` having started its neighbours.

**Decision — the gateway config holds only the datasources that are usable right now.** Toolbox initialises every source eagerly and treats an unreachable or env-incomplete one as a fatal error: a config naming a database that is not up yet exits the container, and with it every project's database access. Since devbot is usually started before the development environment, the config is filtered by a reachability probe and a poller re-renders whenever the usable set changes. Toolbox hot-reloads the rewritten config, so a database that comes up later activates without a restart and one that goes away drops out. A reload that still turns out unavailable is rejected while the previous config keeps serving, so the poller cannot break the gateway.

Two mechanics this depends on fail silently if missed, so both are recorded here: `tools.yaml` is rewritten in place, because toolbox tracks the config file by inode and a file replaced by `mv` is invisible to its reloader; and `up.sh` restarts the poller rather than reusing it, because the poller snapshots the environment at start and a newly added `.env` variable would otherwise leave it and the recreated container disagreeing about what is reachable.

## Why the existing convention is insufficient

- **Existing convention**: `devbot:architecture-rules` lists `network_mode: host` as forbidden; `20260914222815` has gateways ship a static `docker-compose.yml` that `bin/up.sh` discovers, each declaring an in-container healthcheck.
- **Where it falls short for this case**: a bridged gateway cannot reach a database published on the host's loopback, and the mismatch is silent — the host probe succeeds while the container is refused (reproduced against a Postgres published on `127.0.0.1`: `dial tcp 172.17.0.1:15432: connect: connection refused`). A static compose file cannot carry a dynamic set of environment variable names. A distroless image cannot run a healthcheck command at all.
- **What was tried first**: the conforming shape was built and tested before deviating — `ports: 127.0.0.1:18510:18510`, `extra_hosts: host.docker.internal:host-gateway`, and a probe that translated that name back to `127.0.0.1`. It worked for remote databases and failed for host-local ones, which is the common case on a development machine. The generated compose was likewise a fallback: a static module compose passing `env_file:` was tried and rejected because it can carry only the repo `.env`, never the shell environment the operator actually uses.

## Consequences and follow-up work

- `network_mode: host` is Linux-only. macOS and Windows Docker Desktop would need `host.docker.internal` and databases published on `0.0.0.0`; that path is noted in `compose.tpl.yml` but is not exercised.
- The gateway carries no resource limits. If it ever becomes a noisy neighbour, limits are the first thing to add.
- Adding a datasource whose variable is not already in the container needs a `devbot up`, because the env list changes and compose recreates. Adding one that reuses an existing variable activates with no restart.
- An unknown toolset path answers `200` with a JSON-RPC error rather than a 404, so a mistyped datasource name surfaces at call time, not at connect time.

### Proponents: Herberto

### Deciders: Herberto

### Date: 2026-09-17
