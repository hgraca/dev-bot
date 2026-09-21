---
date: 2026-09-21
keywords: ["mcp", "codebase-memory-mcp", "cache-dir", "xdg-cache-home", "store-path"]
trigger-on: ["codebase-memory-mcp-store", "mcp-server-cache-dir"]
---

## `codebase-memory-mcp`'s store is `$HOME`-derived and not relocatable

Its index store lives at `$HOME/.cache/codebase-memory-mcp/` (one `.db` per indexed repo path) and cannot be pointed elsewhere: `codebase-memory-mcp config list` exposes only `auto_index`, `auto_index_limit`, `auto_watch`, `ui-lang`, `ui_enabled`, `ui_port`, and **`XDG_CACHE_HOME` is ignored** — redirecting it and indexing a throwaway repo still wrote the `.db` into the real `~/.cache/codebase-memory-mcp/` while the redirect dir stayed empty (measured 2026-09-21). That is the probe worth running before assuming any engine's cache dir follows XDG: set `XDG_CACHE_HOME`, run one write, and see where the artefact lands. The only lever is `HOME` itself, so relocating the store means overriding `HOME` for every invocation including the host binary — and the host binary and a containerised MCP server must resolve the SAME path, which is why such a container bind-mounts the store at its absolute path and injects `HOME` as the host home instead of mounting all of `$HOME`. Consequence for a dockerised gateway: the store must be mounted at exactly that path, and the host-side directory must exist and be owned by the invoking user before the container starts, or the daemon creates it root-owned (see the docker note on bind-mount sources). Contrast `mdctx`, whose index location IS configurable via `MDCTX_ROOT`/`MDCTX_INDEX` — which is why its store can live under `<devbot>/storage/.mdctx` while this one cannot move.
