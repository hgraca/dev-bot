---
date: 2026-11-26
keywords: ["devbot", "opencode-v2", "plugin", "harness", "required-plugins"]
aliases: ["tui part vanishes after linking", "retire stale plugin dirs", "wired to the wrong harness"]
---

## A dev-bot TUI part is a plugin package under `hooks/`, and the manifest must name it

The v2 harness has no `tui-plugins` farm. A TUI plugin ships as the `./tui` export of a **plugin package**: a directory under `src/harnesses/opencode-v2/hooks/<name>/` holding `index.ts` (the server part, possibly empty) and `tui.ts`. `_link_harness_hooks` links any such directory, and `_write_plugin_manifest` gives it a `package.json` whose `exports` carries `"./tui": "./tui.ts"`.

Two traps. A package **not listed in `src/harnesses/opencode-v2/required-plugins.jsonc`** is deleted immediately after linking by `_retire_stale_plugin_dirs` — the link succeeds and then the package is gone, with no error. And the v2 harness's `up.sh` is only a version guard, so a seeded project picks a new package up on `devbot init`/`reinit`, never on `devbot up`.

Before adding anything to a harness, check which one the project actually runs — `harness` in `.devbot.project.jsonc` (opencode 2.3 here means `opencode-v2`). The two harnesses are deliberately separate: v1's `init.sh` sweeps v2 plugin dirs away, and a plugin written for the wrong one is simply never loaded.
