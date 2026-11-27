---
date: 2026-11-27
keywords: ["devbot", "config", "reinit", "mcp"]
aliases: [".devbot.global.jsonc survives update", "is not dev-bot's leaving it alone"]
trigger-on: ["devbot-global-config", "devbot-reinit-mcp"]
---

## The devbot global config survives `update`, but runtime MCP ownership decides what reinit rewrites

Hand-added keys in `~/.local/share/dev-bot/.devbot.global.jsonc` are durable: `install.sh` skips the file when it exists, and `update.sh`'s `reconcile_global_config.py` removes only **top-level** keys absent from `.devbot.global.dist.jsonc` while merging just `modules` and `external_modules` additively — every other nested object is treated as opaque, so a custom `netsuite: { … }` block (with `{env:VAR}` / `{file:path}` indirection) is neither pruned nor reset. What reinit does _not_ do is touch a runtime MCP manifest it cannot prove it wrote: without a matching record in `.opencode/.owned.*`, `_devbot_apply_runtime_mcps` prints `<group>: .opencode/<group>.mcp.json is not dev-bot's — leaving it alone` and both the manifest and its `opencode.jsonc` entry stay exactly as they are. That cuts both ways — a hand-edited entry is safe from reinit, but a module improvement (a new `oauth` block, a changed URL) will never reach a project whose manifests predate the ownership record, so re-check such files after upgrading instead of assuming the module's output landed.
