---
date: 2026-09-29
keywords: ["codebase-memory", "auto-watch", "watcher", "index"]
---

# The codebase-memory gateway's auto_watch watcher starts but never fires

`codebase-memory-mcp` exposes `auto_watch` (default `true`, "Register background
git watcher on session connect"), and `tools/index-project.sh` used to claim the
watcher kept the index fresh afterwards. Empirically it does not.

Evidence: the whole `/srv/cbm/store/logs/cbm-daemon.log` holds `watcher.start` (9)
and `watcher.stop` (3) and **zero** `watcher.changed` events, while
`check_index_coverage` reports files created after the last explicit index as
`freshness: not_tracked`. Two probes confirmed it — a working-tree write under
`src/`, then the same file `git add`-ed — each left 70s (well past the daemon's
`interval_ms=multi-sec`) with no reindex, no growth in the index generation, and
no change event. The daemon is client-scoped (`watcher.stop` on
`daemon.runtime_stopping reason=last_committed_client_disconnected`), so the
watcher only exists while a harness is connected.

Do not rely on `auto_watch` to keep the index fresh. dev-bot primes explicitly —
`devbot up` before the harness, and a `command.after` hook on agent-run
`git commit`. To force a refresh regardless, call the `index_repository` MCP tool.
