---
date: 2026-11-25
keywords: ["herdr", "window_title", "terminal_title", "opencode", "terminal title"]
aliases: ["terminal title shows opencode session", "OC | title", "window title template"]
superseded_by: ["herdr/20261127090718-herdr-app-uses-json-config-not-toml.md"]
---

## Put the agent session title in herdr's outer terminal title

> **Superseded by** `herdr/20261127090718-herdr-app-uses-json-config-not-toml.md` (2026-11-27) — this
> describes the `config.toml` generation; `herdr-app` configures in JSON under `~/.config/herdr-app`.

herdr keeps two separate titles: `[ui] window_title` — the template it writes to the outer terminal as OSC 0 — and each pane's `terminal_title`, which is whatever that pane's own process emitted. The default template is `"{hostname}: {workspace}"` and omits the pane title, so the terminal window never shows which agent session is running.

opencode already emits `OC | <session title>` (37 chars plus `…` when over 40, `OpenCode` when untitled) as its pane title, so pointing the template at the pane token is the whole fix — no plugin, no polling:

```toml
# ~/.config/herdr/config.toml
[ui]
window_title = "{terminal_title}"
```

Tokens are `{hostname}`, `{workspace}`, `{tab}`, `{pane}`, `{terminal_title}`, with `{{`/`}}` for literal braces; a token with no value renders empty, and `""` leaves the outer title alone. The title follows the **focused** pane, so it shows the session only while an agent pane has focus — a focused shell pane renders its own `user: cwd` title instead, and the `OC | ` prefix plus truncation are opencode's, not herdr's.

Editing `config.toml` does not hot-reload presentation settings: with a server running, follow up with `herdr server reload-config` (it reports `{"status":"applied","diagnostics":[]}`), which is easy to forget because the server persists across terminal restarts and the stale title then looks like a failed change. `herdr config` only offers `check` and `reset-keys` — there is no `config set` — so an installer that must apply this setting has to merge the file in place, backing it up and validating with `herdr config check` rather than overwriting it.
