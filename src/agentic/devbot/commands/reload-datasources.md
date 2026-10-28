---
name: devbot:reload-datasources
description: Re-evaluate the datasource catalogue and verify the shared gateway serves it — the recovery path for a database or data store that was unreachable when devbot started, such as one behind a VPN that was down.
---

Run the reload from the project whose datasources you need:

```bash
devbot datasources reload
```

Then read the output; do not assume success from the exit code alone.

- `reload complete; every selected source is served` — every source the project selects answers a real `tools/list` on the gateway. Enabling its `datasources-<name>` MCP entry now works, and needs no restart.
- `reload applied, but not every selected source is served` — the render did take effect: the config was published, the gateway reconciled and the demanded sidecars started. What failed is the proof, not the apply — read the warnings above it for the source. The command exits non-zero.
- `<name> is published but does not answer` or `is not served at` — the gateway is up but that toolset is not served. The command exits non-zero.
- `selected but still unpublishable: <names>` — the project selects a source the render could not honour: unreachable, missing an environment variable, or not declared in `.devbot.global.jsonc`. Fix the cause and run it again; nothing about the network is hidden from you here.
- `another live project selects what is still unpublishable:` — another session's source was dropped by this render. Report which project is affected; it is not this project's failure.
- `harness manifests are stale: <project>:<source>` — the render moved an endpoint (a re-allocated sidecar port, a different `DATASOURCES_PORT`) and the manifest the harness cached still points at the old one. This is the one case that does need `devbot reinit` and a harness restart; see below.

Do not restart the harness or the session to recover an ordinary datasource: `devbot up` evaluates the catalogue once, at boot, and this command is the explicit re-evaluation — nothing runs in the background. It starts what became reachable (the gateway, and the sidecars live sessions demand) and stops nothing.

The stale-manifest failure is the exception, because the harness has already read the old URL. Run `devbot reinit`, then restart the harness so it reads the rewritten manifest; re-enabling the datasource without that would connect to the endpoint the render has moved away from.

Run it from the owning project — a sidecar is started only for a project a live session is serving.
