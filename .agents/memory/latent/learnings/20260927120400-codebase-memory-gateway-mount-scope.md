---
date: 2026-09-27
keywords: ["codebase-memory", "gateway", "mount", "index"]
---

# codebase-memory can only index paths inside the gateway's repo mount

The codebase-memory gateway is a shared host container that bind-mounts
`${CODEBASE_MEMORY_ROOT:-$HOME}` read-only at the same absolute path. A project
outside that root is invisible to it: `index_repository` fails with a generic
"check repo_path exists and contains source files" hint (misleading — the path is
fine locally), and the session-start hook logged `rc=1` every session
(audit-65/66).

The guard in `tools/index-project.sh` skips priming with a `WARN:` when the
project is outside the gateway's root. Prefer reading the running container's real
bind source — `docker inspect --format '{{range .Mounts}}{{if eq .Type
"bind"}}{{.Source}}{{"\n"}}{{end}}{{end}}' dev-bot-codebase-memory-mcp` — over the
hook process's `CODEBASE_MEMORY_ROOT`/`$HOME`: the env can diverge from the env the
gateway was created with (`up.sh:_reconcile_repo_mount` already treats the
container as authoritative). Fall back to the env only when docker or the
container is absent. A `WARN:` line (not `ERROR`/`failed`) is safe for the
session-end alert matcher, which scans for error verbs only.
