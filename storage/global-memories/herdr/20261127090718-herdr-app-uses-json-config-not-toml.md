---
date: 2026-11-27
keywords: ["herdr", "herdr-app", "settings.json", "hc", "config"]
aliases: ["herdr config.toml is gone", "where are herdr settings", "herdr settings.json"]
supersedes: ["herdr/20261125192544-03-herdr-window-title-follows-pane-title.md", "herdr/20261126073210-03-pane-border-label-from-pane-rename.md"]
---

## herdr-app configures in JSON under `~/.config/herdr-app`, not `config.toml`

The current generation is `herdr-app` (the GUI at `/Applications/Herdr.app`) plus `hc`, the
herdr-core terminal server those terminals live in. It has no `config.toml` and no `herdr server
reload-config`: settings are plain JSON files in `~/.config/herdr-app` (`HERDR_APP_HOME` overrides),
written by the app and editable in place — `settings.json`, `keys.json`, `shared.json`,
`view.json`, `window.json`, plus `layouts/*.json`. The binary is not on `PATH` by default; the bundle
one answers `--help`, `commands`, `status`, `ls`, `shot`, `--skill`. `hc` lives on `PATH`
(`~/.local/bin/hc`) and is the agent-facing half: `run`, `ls`, `read`, `send`, `keys`, `wait`, `put`,
`exec`, and `wait` explicitly exists so an agent waits on a terminal instead of sleeping.

`settings.json` is documented in the app's own `AGENTS.md` (same folder, section "The person") and
takes `zoom`, `sounds` (`enabled`, plus `done`/`blocked` file paths, absolute or relative to the config
folder), `core`, `worktrees.directory`, `terminal_line_height`, `terminal_cell_width`,
`terminal_scroll_speed`, `font*`, `theme`, `colors`, `appearance`. Changes apply live; check
`herdr-app status` reports `"errors": []` when the file parsed.

Keybindings are `keys.json` with `global` and `terminal` scopes mapping chord to a command name, and
`command:argument` works (`pane.split:right`, `tab.select:1`). Get the real command list and each
command's required arguments from `herdr-app commands` — the bindable and useful set is smaller than
it looks, because most commands accept a required target that a bare chord cannot supply.

Pane borders and the outer title are two different things: the border label comes from
`pane rename` (dev-bot's herdr plugin claims it), while the window title template in this
generation is not the `[ui] window_title` key the older notes describe.
