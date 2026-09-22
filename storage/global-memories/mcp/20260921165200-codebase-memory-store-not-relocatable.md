---
date: 2026-09-21
keywords: ["mcp", "codebase-memory-mcp", "cache-dir", "xdg-cache-home", "store-path"]
trigger-on: ["codebase-memory-mcp-store", "mcp-server-cache-dir"]
---

## `codebase-memory-mcp`'s store is `$HOME`-derived and not relocatable

Its index store lives at `$HOME/.cache/codebase-memory-mcp/` (one `.db` per indexed repo path) and cannot be pointed elsewhere: `codebase-memory-mcp config list` exposes only `auto_index`, `auto_index_limit`, `auto_watch`, `ui-lang`, `ui_enabled`, `ui_port`, and **`XDG_CACHE_HOME` is ignored** — redirecting it and indexing a throwaway repo still wrote the `.db` into the real `~/.cache/codebase-memory-mcp/` while the redirect dir stayed empty (measured 2026-09-21). That is the probe worth running before assuming any engine's cache dir follows XDG: set `XDG_CACHE_HOME`, run one write, and see where the artefact lands. The only lever is `HOME` itself, so relocating the store means overriding `HOME` for every invocation including the host binary — and the host binary and a containerised MCP server must resolve the SAME path, which is why such a container bind-mounts the store at its absolute path and injects `HOME` as the host home instead of mounting all of `$HOME`. Consequence for a dockerised gateway: the store must be mounted at exactly that path, and the host-side directory must exist and be owned by the invoking user before the container starts, or the daemon creates it root-owned (see the docker note on bind-mount sources). Contrast `mdctx`, whose index location IS configurable via `MDCTX_ROOT`/`MDCTX_INDEX` — which is why its store can live under `<devbot>/storage/.mdctx` while this one cannot move.

## Amendment (2026-09-22): the store IS relocatable — `CBM_CACHE_DIR`

The conclusion above ("the only lever is `HOME`") is **wrong**, and the probe was under-specified: it tested `XDG_CACHE_HOME` and stopped there. The engine also honours **`CBM_CACHE_DIR`**, which sets the cache root directly and is the documented lever (vendor README; the variable appears in the binary's own env list). Verified live: a gateway with `HOME=/srv/cbm` and `CBM_CACHE_DIR=/srv/cbm/store` writes its store to `/srv/cbm/store` and never touches `$HOME/.cache`.

That is exactly how the module relocated its store off a host bind mount and onto a Docker named volume (see ADR `20260914222815`'s 2026-09-22 amendment) — which also retires the bind-mount ownership trap this note ends on, since there is no host path left to own. Generalisation, replacing the "only lever" claim: probe the engine's **own** environment variables and CLI, not just the XDG convention, before declaring a path fixed.
