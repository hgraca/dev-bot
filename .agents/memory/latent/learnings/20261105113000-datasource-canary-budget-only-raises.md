---
date: 2026-11-05
keywords: ["datasources", "canary", "timeout", "readiness", "toolbox"]
aliases: ["did not become ready within", "DATASOURCES_CANARY_TIMEOUT", "readiness budget"]
---

# The datasource canary budget may only be raised, never lowered

## What the message actually means

`toolbox did not become ready within Ns` is not "the database is down". The canary container is
still **running** — `docker_canary` checks `State.Running` and only falls through to this branch
when the container never exited — it simply never answered `/healthz`.

On 2026-11-05 a healthy staging RDS source (`gete-dev-3.<zone>.rds.amazonaws.com`) was dropped this
way while TCP 3306 connected fine and the pinned toolbox initialized it in 1.1–1.7s, measured over
six standalone runs. So the 5s budget was a margin problem, not a reachability problem.

Also read the render line carefully: `config unchanged` means the _previous_ render had already
excluded that source. A missing toolset at session start usually predates the `reload` the operator
just ran — the reload only re-evaluates it.

## Why a floor derived from ENGINES is unsafe

`render_tools_yaml.ENGINES` declares 2s dial bounds (mysql `timeout: 2s`, pgx `connect_timeout: 2`)
and mongodb's rides in the URI. But `uri_timeout_params` are appended **only when the operator has
not set them** — that is the documented escape hatch — so
`...?serverSelectionTimeoutMS=30000` renders a 30s driver bound the engine table knows nothing
about. Any floor computed from `ENGINES` would therefore accept a budget that still pre-empts the
driver and buries the named `i/o timeout`.

The rule that shipped instead: the override must be `>= DEFAULT_TIMEOUT` (15s). The knob only ever
raises the budget, so no accepted value can reintroduce the original regression.

## Budget arithmetic, and the `inf` trap

`MAX_PARALLEL_CANARIES = 8`, so the budget bounds **one wave**, not the render — a catalogue past
eight sources spans a wave per batch. It never multiplies by source count, which is what made
raising 5s to 15s affordable: a slow source costs one budget, not one per source.

`float()` happily parses `inf` (and `1e400`, which becomes `inf`); an infinite deadline makes the
readiness poll never terminate and hangs the render instead of failing. `_parse_args` rejects
non-finite and non-positive values before any container starts.
