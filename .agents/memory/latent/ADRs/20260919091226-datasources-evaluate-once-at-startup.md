---
date: 2026-09-19
keywords: ["datasources", "mcp-toolbox", "startup", "poller", "availability"]
see: ["ADRs/20260918130000-datasources-measure-availability-with-the-real-toolbox.md", "ADRs/20260917204927-datasources-gateway-host-network-generated-compose.md"]
---

## Evaluate datasources once, at startup

The `datasources` catalogue is evaluated a single time, when `devbot up` runs, and only the sources usable then are loaded into the shared gateway. Nothing refreshes in the background: a database that comes up later is not picked up until the next `devbot up`, and one that goes away is not pruned mid-session. This replaces the refresh poller, whose job was lazy activation.

The poller was never optional under the old constraint — mcp-toolbox treats a source it cannot initialize as fatal at startup _and_ on reload, so the published config had to contain only sources the gateway accepts, and something had to keep re-measuring. But it earned little for what it cost. Reachability was only re-measured when `DATASOURCES_VALIDATE_INTERVAL` (300s) elapsed, so "my database just came up" was noticed in minutes, not on the 10s tick; and the MCP client does not self-heal an absent server, so a toolset appearing mid-session may not surface at all without a harness restart. Meanwhile it was a detached `while true` with no backoff: a render that failed never updated the validation timestamp, so re-validation stayed permanently due and it re-ran a canary container every ~10 s forever. That is exactly what a blackholed host produced — one that drops packets never becomes ready _or_ exits, so the canary could not name a culprit, the render aborted, and boot both stalled and never converged.

Three consequences are part of the same decision. The render gate no longer refuses to publish an empty config: with one evaluation, "not usable now" means "not loaded", and keeping the previous config would only point the gateway at sources it cannot initialize — fatal to it. An inconclusive validation still aborts, because the validator exits non-zero and `pipefail` fails the pipeline before anything is written. The quarantine state goes with the poller, since a backoff that survives boots only delays a database that has come back. And each engine's dial is bounded where toolbox allows it — `queryParams` for mysql and postgres, URI parameters for mongodb; redis exposes no dial timeout in 1.11.0 — so an unreachable host fails fast and is _named_, which is what the drop machinery needs.

This is a deliberate workaround for a toolbox limitation, not the desired end state. Upstream is adding `--allow-partial-sources` (mcp-toolbox PRs #2662 / #2959), verified absent from 1.11.0 and 1.12.0. When it ships, the gateway can serve the full catalogue and a single unreachable source degrades only its own tools — the filter, the canary and the drop loop can all be deleted. Do not build new filtering machinery before then.
