---
date: 2026-11-05
keywords: ["devbot", "reinit", "tui-plugins", "symlink"]
aliases: ["tui plugin link farm", "unmerged plugin disappears"]
---

# Reinit deletes TUI plugin links for anything not in the main checkout

`reset.sh` sweeps `.opencode/tui-plugins/` and `init.sh`'s `_link_tui_plugins` rebuilds it from `_TUI_PLUGINS` **as the main checkout defines it**. A plugin that exists only on an unmerged branch has no entry there, so every `devbot init`/`reinit` removes its symlink and leaves `tui.json` pointing at a missing directory — the plugin silently stops loading, and a hand-made link is undone by the next reinit.

## While trialling an unmerged plugin

Either accept that each reinit needs the link recreated, or point the `tui.json` entry at an absolute `file://` path into the worktree (reinit leaves `tui.json` alone — it is seed-once and additions-only). Both are interim: after merge, `_link_tui_plugin` relinks to `dev-bot/src/harnesses/opencode/<name>` because the link target no longer matches.

## Confirming which build actually loaded

`~/.local/state/opencode/plugin-meta.json` records per-plugin `load_count`, `first_time`, `last_time`, and the source's `modified` mtime. A link deleted and restored without an opencode restart keeps the old build's counts — watch `load_count` increment after the restart, not merely the entry existing.
