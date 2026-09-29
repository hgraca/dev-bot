---
date: 2026-09-29
keywords: ["codebase-memory", "index-priming", "up.sh", "hooks", "command.after"]
---

## Prime the codebase-memory index on `devbot up` and on agent-run commit

The codebase-memory index is primed by the module's `up.sh` — before the harness
starts, since `bin/devbot` runs `bin/up.sh` and only then the harness `start.sh` —
and re-primed by a `command.after` hook matching `git\s+commit`, mirroring
graphify's trigger rather than a `.git/hooks` script. This replaced a
`session.created` hook, which (a) only reflected the last session start and no
later commit, (b) raced the boot — a harness started before `devbot up` found the
gateway down and skipped indexing — and (c) leaned on the engine's `auto_watch`
watcher for mid-session freshness, which never fires.
`tools/index-project.sh` remains the single guarded entry point (active provider,
gateway reachability, `src`/`app` resolution, mount scope) and launches the actual
index detached, so `up.sh` returns at once and a failed index never fails the
boot. Priming is deliberately not gated on `_devbot_wait_for_mcp_gateway`, which
returns 1 when curl is absent — index-project.sh probes the gateway itself
(bash `/dev/tcp`). Accepted gap: `command.after` fires only for commits run
through the agent's bash tool, so a terminal or PTY commit does not re-prime.
