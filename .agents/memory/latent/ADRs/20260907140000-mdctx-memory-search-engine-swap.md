---
date: 2026-09-07
keywords: ["mdctx", "memory_search_provider", "engine swap", "search-memories"]
see: []
---

## mdctx module + memory_search_provider engine swap

dev-bot gained a second memory-search engine: a new agentic module
`src/agentic/mdctx` wraps the zero-ML npm package `mdctx` (RAKE + BM25 over a
flat git-diffable `context-index.json`; no embeddings/GPU) as a sibling to the
existing `qmd` module (hybrid semantic + BM25, llama/GPU). The active engine is
chosen by the global-only key `memory_search_provider` in
`.devbot.global.jsonc` (`"qmd" | "mdctx"`, absent ⇒ `mdctx`), mirroring the
reviewed `codebase_index_provider` precedent: `_devbot_get_memory_search_provider`
reads the key, `_devbot_get_disabled_modules` appends the non-selected engine to
the disabled set (both engine pairs are mutually exclusive independently), and
the opencode harness reset prunes stale/disabled MCP entries on reinit.

The agent-facing memory-search entry point stays **`search-memories`** — it
searches the CURRENT project vault + the shared global store under both
engines "as it previously worked" (qmd: `-c <project> -c dev-bot-global`;
mdctx: two flat indexes, project + global, merged and deduped by absolute
path, bodies read from disk since mdctx has no `get`). Each engine is isolated
in its own functions (`search_qmd`/`search_mdctx`, `fetch_file_body`/
`fetch_mdctx_body`) and dispatched on the provider — no qmd-shaped shim. The
reindex/prune tools, the detached start.sh prune, and the global-store
registration in `memory/init.sh` dispatch the same way (mdctx reindex =
incremental `mdctx build` of project + global indexes; no cleanup/embed).

Decisions recorded with the stakeholder: engine skills are named
`devbot:qmd` / `devbot:mdctx` and stay registered when their engine is
selected, but no agent instruction or skill references them for memory search —
everything routes via `search-memories` (the qmd skill is qmd-specific and is
not the abstraction). Index homes are gitignored and engine-owned: project
index at `<project>/.mdctx/context-index.json`, global index at
`${DEV_BOT_ROOT}/storage/.mdctx/context-index.json` (mdctx ignores symlinks,
so each real root is indexed separately). The prune/reindex log was renamed to
`.agents/logs/memory-index.log` for BOTH engines. MCP registration resolves a
`__DEV_BOT_ROOT__` path-prefix placeholder at init (mirroring
`__GPU_ENABLED__`); `mcp_key_is_current.py` treats it as current-any-value with
a matching suffix. The mdctx MCP server roots at the global-memories store via
`MDCTX_ROOT`/`MDCTX_INDEX` (index written to gitignored storage/.mdctx, so the
auto-heal never pollutes the tracked store). Live config is pinned to `"qmd"`
locally; flip = change the key + `devbot reinit`.
