---
date: 2026-09-28
keywords: ["graphify", "up.sh", "cache", "prune", "nohup"]
---

# Graphify cache is pruned on `devbot up` via a new module up.sh

The graphify module had no `up.sh`; `bin/up.sh` auto-discovers `src/agentic/<module>/up.sh`, runs it after docker services with the project directory as `$1`, and skips disabled modules. `src/agentic/graphify/up.sh` prunes files under `$PROJECT_DIR/graphify-out/cache` older than `CACHE_MAX_AGE_DAYS` (`GRAPHIFY_CACHE_MAX_AGE_DAYS`, default 7) and runs detached — `( nohup find "${cache_dir}" -type f -mtime "+N" -delete & )` — so a scan over a 60k-file cache never delays boot; it is non-fatal by design. Two consequences worth remembering: `nohup` cannot run a shell function, so the detached payload must be a binary (here `find`); and its tests must poll for the detached effect (`tests/up_tests.bats`) rather than assert immediately after the script returns.
