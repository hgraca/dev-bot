---
date: 2026-10-23
keywords: ["shell", "worktree", "hosts", "makefile", "dev-tools"]
aliases: ["WORKTREE_PREFIX", "PROJECT_BASE", "ensure-hosts --remove", "worktree host collisions"]
---

## Worktree host and database identity rules

Worktree isolation in the GET-E dev-tools Makefile needs three separate identity rules, and conflating them produces silent collisions. The Compose project name may contain `_` but a hostname label may not, so host-facing values (`WORKTREE_PREFIX`, `PROJECT_BASE`, `TRAEFIK_SUBDOMAIN`) must be derived through a dashed form. Slugging is not injective (`feature.v1` vs `feature-v1`, `a_b` vs `a-b`, case-only differences), so any name that had to be transformed needs a short digest of its **absolute path**, and the fast path must only accept already-valid, boundary-clean labels (no leading/trailing `-`). Normalise `PROJECT_BASE` with `override` so a command-line value cannot bypass it, and keep the make-level and exported values identical or `init-hosts` and Traefik will disagree.

Worktree teardown needs `scripts/ensure-hosts.sh --remove <hosts>`; dropping that mode breaks the documented cleanup in `devbot:git-worktrees`. The helper must also match CRLF entries, abort on grep status > 1 before rewriting, and serialise the read-modify-write (`flock`) so a concurrent add is not lost. A Perl-less container (PHP-FPM images) cannot run the supervisor-based `timeout.sh`, so it must fall back to `timeout`/`gtimeout` rather than failing closed.
