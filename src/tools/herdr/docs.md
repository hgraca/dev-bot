---
title: "Herdr"
description: "Agent-runtime terminal workspace manager, wired to own the devbot docker stack."
---

[Herdr](https://herdr.dev) is a terminal workspace manager for AI coding agents: sessions, panes and remote hosts in one TUI.

## What this module installs

- **The `herdr` binary**, through the project's own installer (`curl -fsSL https://herdr.dev/install.sh | sh` — release manifest, SHA-256 verified, into `~/.local/bin`). Linux and macOS; an installed herdr is left alone.
- **The window-title setting**: `window_title = "{terminal_title}"` under `[ui]` in `~/.config/herdr/config.toml` (or `$XDG_CONFIG_HOME/herdr/`), so the terminal title follows the focused pane's agent session. An existing key is never touched, a config that the key would break is reverted, and a running server is reloaded.
- **The `herdr` shell function**, in `~/.bashrc` and `~/.zshrc` — whichever exist.

## The shell function

dev-bot owns the wrapper, not the shell rc. It is rendered into a marked block:

```bash
# >>> devbot:herdr >>>
…
# <<< devbot:herdr <<<
```

and every `devbot install` / `devbot update` re-renders it, so a change to the wrapper reaches the machine with a release. Anything else that defined a `herdr` function first — a hand-rolled one, or the block an older setup script appended — is removed before the managed block is written, so the shell never keeps running a copy dev-bot no longer manages.

The wrapper makes herdr the **owner** of the docker stack: it runs `devbot up --owner herdr --owner-pid $$` before the TUI starts and `devbot down --owner herdr --owner-pid $$` when herdr exits. That is what keeps a devbot session opened inside a herdr pane from tearing down containers herdr started — see [Container ownership](/modules/tools/devbot-cli) for the registry behind it. Non-launch invocations (`herdr completion`, `herdr --machine …`) pass through untouched.

## The devbot marker token

`devbot` running inside a pane publishes the terminal marker that ended its turn as **display-only
pane metadata** — the `devbot` token, e.g. `devbot=NEEDS_INPUT`. It is not a state report: the
pane's lifecycle authority stays with `herdr:opencode`, so the agent keeps its name and its
`idle`/`working`/`blocked` state. The token has no TTL: it stays until the next turn replaces or
clears it, or the pane closes — so treat it as the last marker reported, not proof of a live state.

Read it with `herdr pane get <pane>` or `herdr agent list`; the default sidebar rows do not show
metadata tokens, so add it to a row to see it:

```toml
[ui.sidebar.agents]
rows = [["state_icon", "machine", "workspace", "tab"], ["agent", "$devbot"]]
```

The token follows the turn:

```bash
herdr agent list | jq '.result.agents[] | {pane: .pane_id, marker: .tokens.devbot}'
```

`tokens` is omitted from the response while unset, so a pane without a marker has no `devbot`
key. It is written from `session.idle` in the pane's own process, so a server shared across
panes reports to the pane that spawned it, and it is absent wherever herdr is not running.

## Enablement

**Disabled by default**: opt in with `"modules": { "herdr": true }` in `.devbot.global.jsonc`, then run `devbot install`. The **global** map is the switch: install and update provision the machine, not a project, so a project-file entry changes nothing here. A disabled module installs nothing and leaves both shell rcs untouched — it is not removed from them, so a block a previous install wrote stays until you delete it.

The `1.25.0` migration writes the explicit `false` for a config that names neither module, and leaves a value the machine set itself alone — the module scripts run before the reconciler, so the default has to be there first.
