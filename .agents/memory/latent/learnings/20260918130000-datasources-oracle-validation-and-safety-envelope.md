---
date: 2026-09-18
keywords: ["datasources", "oracle", "mcp-toolbox", "quarantine", "validate-catalogue"]
---

# datasources: the toolbox oracle, its safety envelope, and how to test it

**Superseded in part (2026-09-19).** The pipeline below is the poller/quarantine era: datasources are now evaluated once at startup, the poller and the quarantine state are gone, and each source is canaried on its own rather than as one combined candidate — see `ADRs/20260919091226-datasources-evaluate-once-at-startup.md`. The mcp-toolbox facts and the docker-free testing notes below still hold.

## The pipeline that decides what the gateway serves

`render.sh` pipes the catalogue through `available_catalogue.py` (env-completeness only — it opens no socket), then `validate_catalogue.py` (the oracle), then `render_tools_yaml.py`; it skips the publish when the result is byte-identical, and otherwise `cp`s it in place (inode preserved for toolbox's reloader). The oracle runs the pinned image detached (`docker run -d`, deliberately **without** `--rm` so `docker logs` still works after it exits) and polls `inspect` then `/healthz`; a named culprit is dropped and the reduced candidate re-tried, bounded by the catalogue size. Failures are recorded in `storage/datasources/quarantine.json` — an entry is excluded (and not re-tested) until its backoff elapses, and entries for sources no longer declared are pruned, otherwise a stale entry's retry is permanently due and the poller re-runs a canary every cycle. The poller re-renders on a candidate-set change OR when `quarantine.py needs-revalidation` says a retry is due (default 300s). Renders are serialized by a `flock` (`_devbot_lock_wait`), and `up.sh` stops any existing poller before rendering.

## mcp-toolbox 1.11.0 facts this depends on (verified against the pinned image)

`--config-folder` **merges every `.yaml`/`.yml` file** in the directory into one config, so per-file isolation is impossible. Any source it cannot initialize is **fatal at startup and on reload** — one bad source takes the whole gateway down, which is why the config may only ever contain sources it accepts. A rejected reload is **retried on every `--poll-interval`** (5s in this module), so a rejected publish must be undone rather than left on disk. `/healthz` returns 200 once the server is ready (added in 1.8.0), a precise readiness signal. The CLI prints `unable to initialize source "X"` — escaped in the logger line, plain on the error line — and `--disable-version-check` stops the startup version call. Crucially, `--allow-partial-sources` / per-source `checkAtStartup` do **not** exist up to 1.12.0, so "tolerate a bad source" is not available and the filter is mandatory.

## Testing it without docker (and the trap that costs 6s per test)

The unit suites must stay docker-free: the BATS suite exports `DATASOURCES_VALIDATOR` to a stub, and `test_validate_catalogue.py` injects a `runner` into `docker_canary`/`validate`. The BATS setup also has to stub `docker` on `PATH` — with the real daemon and a live `dev-bot-datasources-mcp` container present, `render.sh`'s publish verification slept a full reload interval and scraped the real gateway's logs, hanging the suite. One committed real-container e2e (skipped when the image is absent) is what proved the oracle's verdict matches the gateway, and an e2e of that kind is what caught the earlier MongoDB tool-shape blocker that docker-free tests could not.
