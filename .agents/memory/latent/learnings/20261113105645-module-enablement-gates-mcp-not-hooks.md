---
date: 2026-11-13
keywords: ["devbot", "hooks", "modules", "enablement", "graphify"]
aliases: ["disabled module still runs hooks", "phantom hook", "session.created fires anyway"]
---

# Module enablement gated the MCP registration but not the hooks

## The trap

`modules.<name>: false` stopped the MCP server from being registered, but `on-hooks.ts` `loadManifests()` globbed **every** `$DEV_BOT_ROOT/src/agentic/*/hooks.json` and wired its hooks regardless. So a disabled module kept firing its `session.created` hook in every project.

Observed on the polyrepo root, where `graphify` is disabled and has no code: `graphify update .` ran on every session for weeks — 112 times, each logging "No code files found", each recreating a stale `graphify-out/` placeholder. The tell is a `graphify-out/.graphify-update.log` in a project that has no business having one.

## The rule is not just the `modules` map

Re-deriving "is this module enabled" from the two `modules` maps is **wrong**. The canonical resolver `_devbot_get_disabled_modules` (in `src/_shared/functions.sh`) also disables:

- the non-selected codebase engine (`codebase-index` vs `codebase-memory`, by `codebase_index_provider`);
- the non-selected memory-search engine (`qmd` vs `mdctx`, by `memory_search_provider`);
- every harness the root `harness` key did not select.

At the Get-e root it returns **11** disabled modules where the `modules` maps name 3. Ask the resolver rather than duplicating it: `bash -c 'source "$1"; _devbot_get_disabled_modules "$2"' _ "$functions" "$project"` — pass the paths as **arguments**, never interpolated into the script, or a workspace path containing `$(…)` executes.
