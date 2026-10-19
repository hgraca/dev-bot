---
date: 2026-10-16
keywords: ["worktree", "dev-tools", "traefik", "compose", "makefile"]
aliases: ["worktree host isolation", "WORKTREE_PREFIX", "PROJECT_BASE", "worktree compose project"]
---

# dev-tools worktree host scheme (PROJECT_NAME / WORKTREE_PREFIX / PROJECT_BASE)

A dev-tools consumer's Traefik host is built from variables the managed `Makefile` exports;
getting one wrong silently points every worktree at the main checkout.

- `PROJECT_NAME` — compose project, container names and router/service names. The managed
  Makefile re-assigns it to the **worktree directory name** _after_ including `Makefile.proj.mk`
  (with `override`), so a proj.mk `PROJECT_NAME=transfers` (plain `=`) no longer defeats it.
  That clobber was the bug: every worktree targeted `transfers-app-1` and ran against the main
  checkout's code.
- `TRAEFIK_SUBDOMAIN_PREFIX` (+ `PROJECT_BASE`) — for a **single host with no main subdomain**:
  `Host(\`${TRAEFIK_SUBDOMAIN_PREFIX}${PROJECT_BASE}.get-e.local\`)`. It is not worktree-scoped
once `TRAEFIK_SUBDOMAIN` is set, so a project with a main subdomain must not use it.
- `WORKTREE_PREFIX` — empty in the main checkout, `<dir>.` in a worktree. For **multi-host or
  subdomain** projects: prefix the _literal_ main host, e.g.
  `Host(\`${WORKTREE_PREFIX}api.hotels.get-e.local\`)`. This is the only form that scopes every
  host without changing the main checkout.
- `PROJECT_BASE` must be **declared** (`PROJECT_BASE ?= <base>`). Capturing it from `PROJECT_NAME`
  only works when the project hard-assigns that (`=`); with `?=`/unpinned, `PROJECT_NAME` is
  already the worktree directory at capture time and the host becomes `<dir>.<dir>.get-e.local`.

Two traps that a `Host(...)`/port-only check misses:

- The compose **`name:`** must be `${PROJECT_NAME:-<base>}`. A literal `name: exchange-rate`
  keeps the project name fixed, so a worktree hijacks the main checkout's containers and `make up`
  fails at `docker exec ${PROJECT_NAME}-app-1` ("No such container"). Four consumers shipped this.
- Core's DB key is **`DB_API_DATABASE`** (not the template's `DB_DATABASE`), so the per-worktree
  `.env` rewrite must use the project's real key — plus `DB_MONGO_DATABASE`.

Hosts flow: `host-requirements/run.sh` (run by the managed `up` _before_ `init`/`init-hosts`,
so it covers a worktree `make up` too) makes `/etc/hosts` writable via
`hosts-file-permissions/fix.sh` (self-elevating). Once writable,
`scripts/ensure-hosts.sh` adds/removes the per-worktree entries with no sudo — and the worktree
teardown removes them. The Composer plugin copies `src/Bash` → `scripts/` but never prunes, so
consumers accumulate files that were deleted upstream (e.g. `fix.linux.sh`).
