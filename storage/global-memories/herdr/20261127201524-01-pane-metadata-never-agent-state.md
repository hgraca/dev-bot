---
date: 2026-11-27
keywords: ["herdr", "report-metadata", "report-agent", "lifecycle-authority", "pane-token"]
---

## Publish pane metadata, never agent state, unless the publisher owns the pane

`herdr pane report-agent` hands a source lifecycle authority over a pane, and on 0.9.5 that is destructive and one-way: a foreign report replaced a screen-detected pane's agent label within a second, held it stably, and a later `release-agent` left the pane `unknown` — the agent was never re-detected, even after keypresses. A first report of `working` from a source that does not yet hold the pane is accepted (rc=0) and ignored; `idle` or `blocked` claim it. A source whose id starts with `herdr:` is silently ignored, so another integration's authority cannot be emulated. `herdr pane report-metadata --token name=value` is display-only: the token appears while the agent label, state and authority stay as they were, and clearing it (`--token name=`) leaves nothing behind. Tooling that merely wants to publish a status should use the token and leave `report-agent` to whatever genuinely owns the pane.
