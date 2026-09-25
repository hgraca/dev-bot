---
date: 2026-09-25
keywords: ["opencode", "plugin", "opencode.jsonc", "disabled-module", "reset"]
trigger-on: ["opencode-plugin-registration", "disabled-module-plugin-prune"]
---

## opencode unions two plugin surfaces, so a plugin pruned from one still loads

opencode loads the project's `opencode.jsonc` **and** the opencode-owned `.opencode/opencode.json`, then unions their `plugin` arrays — so anything that removes a plugin entry (disabling a module, flipping an engine provider) must prune **both** surfaces, or the plugin keeps loading while the config that registered it looks clean. The failure is silent in the worst way: the tools stay in the agent's palette and fail at call time instead of being absent — a retired semantic codebase index answered "No embedding-capable provider found" on every context-gathering run long after `codebase_index_provider` had moved to another engine. dev-bot hit exactly this: its `reset.sh` pruned the plugin from `opencode.jsonc` only, so the flipped-off engine's tools survived. The fix prunes each disabled module's `plugin.opencode.json` entries from both surfaces through one pre/post-checked text-surgery helper (`src/_shared/remove_plugin_entry.py`, which preserves comments and byte idempotency). Two things make it easy to miss: the second surface is never seeded by dev-bot (never written by init), so it is not obviously dev-bot's to clean; and the symptom mimics a broken server rather than a stale registration. Diagnose by checking `.opencode/opencode.json`'s `plugin` array whenever a tool is in the palette but its backing server is absent or erroring.
