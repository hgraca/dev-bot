---
date: 2026-11-06
keywords: ["datasources", "docker-desktop", "host-networking", "macos"]
---

# The datasources module has two network modes: Linux host networking, macOS published ports

Host networking is a Linux capability. On macOS Docker Desktop the container's loopback is not the
host's, so the `datasources` module renders a different network shape there — and every loopback a
datasource points at has to move with it.

## What changes on macOS

`on_macos()` (`render_tools_yaml.py`) is the single branch point; `DATASOURCES_PLATFORM`
(`darwin`/anything else) overrides the `sys.platform` detection so one machine can exercise both
modes.

- `render_compose.py`: the gateway gets a loopback-bound published port
  (`127.0.0.1:${DATASOURCES_PORT}:${DATASOURCES_PORT}`) instead of `network_mode: host`, and binds
  `0.0.0.0` inside the container; each sidecar does the same on its fixed port.
- `validate_catalogue.py`: the canary runs with `-p 127.0.0.1:<port>:<port>` and `--address 0.0.0.0`;
  the host still probes `127.0.0.1`, which is exactly what the published port exposes.
- `render_tools_yaml.py`: literal loopback values are rewritten to `host.docker.internal` — the
  whole host token of a URI authority (credentials and port preserved, matched on the authority so
  `localhost.example` and a later `//localhost` are untouched), and the host of a `host:`/`address:`
  value. A `${VAR}` reference name is never rewritten.

## Defaults and reference fallbacks are literals too

The rewrite covers what the renderer _emits_, not just what the user declared. An undeclared
`MYSQL_HOST`/`POSTGRES_HOST` emits `${MYSQL_HOST:localhost}`, and a declared `${HOTELS_DB_HOST}`
gains `:localhost` as its fallback. Toolbox resolves both inside the container, so on macOS both
must say `host.docker.internal` — rewriting only declared literals leaves the documented default
configuration unable to reach a host-local database.

## Tests must pin the platform

The renderers branch on the host platform, so a test that shells out to them and asserts Linux
output fails on a macOS machine. `test_render_tools_yaml.py` and `test_render_compose.py` pin
`DATASOURCES_PLATFORM=linux` in their `render()` helper; Darwin cases pass
`env={"DATASOURCES_PLATFORM": "darwin"}`. Verify both by running a suite with the parent env set:

```bash
DATASOURCES_PLATFORM=darwin python3 -m unittest test_render_tools_yaml
```

The parent env only reaches `subprocess.run` calls that bypass the helper, which is why the pin
belongs in the helper rather than in individual assertions.
