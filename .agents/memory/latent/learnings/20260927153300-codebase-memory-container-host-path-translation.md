---
date: 2026-09-27
keywords: ["codebase-memory", "gateway", "path-translation", "fixture"]
---

# codebase-memory: translating a container path to the gateway's host path

The shared codebase-memory gateway bind-mounts ONE host root at the same
absolute path (default `$HOME`), and `index_repository` resolves paths in the
GATEWAY's namespace. A project mounted at a different container path (the e2e
fixture's `/app`) is therefore invisible to it even when the host directory IS
under the mount.

Two changes make the fixture indexable (commit `a30f70b2`):

- `bin/up.sh` derives the gateway root instead of hardcoding `$HOME`
  (`_devbot_codebase_memory_root`: the common ancestor of `$HOME` and the
  existing registered `projects` — never below `$HOME`, never `/`), and exports
  it before compose interpolates the mount.
- the fixture launcher passes `CODEBASE_MEMORY_ROOT=<the gateway's real bind
  source>` (read via `docker inspect` — `test-lib.sh:codebase_gateway_mount`)
  and `CODEBASE_MEMORY_HOST_PROJECT=<the host run dir>`; `index-project.sh` maps
  the project-relative `src|app` subdir onto the host path and scope-checks THAT
  against the gateway root before calling `mcp-index.py`.

Caveat: it only works while the gateway's root is the host `$HOME` (the default)
— reconfiguring that shared gateway makes the fixture skip again. Run dirs live
under `$HOME/.cache/devbot-test` (not `/tmp`) precisely so they fall inside the
default mount.
