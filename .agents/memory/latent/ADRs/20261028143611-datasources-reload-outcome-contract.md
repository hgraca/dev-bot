---
date: 2026-10-28
keywords: ["datasources", "reload", "exit-code"]
---

## `datasources reload` reports a three-value outcome; its counter is toolbox-only

`devbot datasources reload` exits `0` (complete), `1` (the render applied but a selected source is
still unserved) or `2` (nothing applied — a missing `docker`/`curl`, another lifecycle run holding
the lock, or a render abort). Before this, both a partial run and an abort returned `1`, so a caller
could not tell "ran, incomplete" from "never ran", and the message "reload incomplete" implied
nothing had been applied when the config had already been published and the gateway reconciled.
`2` is reserved for aborts because they leave the running config untouched.

Two consequences follow. The `N/M … usable` counter counts **toolbox sources only** — sidecars are
their own containers and never appear in `tools.yaml` — so it is labelled `toolbox source(s)` and is
suppressed entirely when the catalogue declares none; it describes the whole catalogue, not the
project's selection. And the reload is exposed to agents as the `reload-datasources` MCP tool, which
flattens the whole transcript onto stdout and exits `0` for the three documented statuses (it ends
with `reload: complete`, `reload: not complete` or `reload: not applied`), propagating only a
malfunction status: the devbot-tools server surfaces stderr *instead of* stdout once a tool exits
non-zero having written to both, so a partial run would otherwise reach the agent as a bare error
line with every per-source result lost.
