---
date: 2026-11-17
keywords: ["devbot", "pty", "opencode-pty", "opencode-v2", "plugin-ownership"]
aliases: ["own the pty plugin", "drop the opencode-pty dependency", "pty sidebar in devbot"]
supersedes: ["PDRs/20260926180000-sidebar-ships-inside-opencode-pty.md"]
---

## dev-bot owns the PTY plugin locally instead of shipping inside `opencode-pty`

The earlier decision — the PTY sidebar belongs to the upstream `opencode-pty` package, published as its `exports["./tui"]`, not to dev-bot — is reversed for the OpenCode v2 harness. The stakeholder's instruction is that dev-bot must not depend on that upstream any more: the PTY extension (the five tools, the session-info shape and the sidebar monitor) is owned locally in this repo, under `src/harnesses/opencode-v2/hooks/pty.ts` plus a TUI part in the same package, and is linked only when `harness: "opencode-v2"` is selected. Additions proposed upstream in `shekohex/opencode-pty#91` (`parentSessionId` on `PTYSessionInfo`, so a client can attribute and filter PTYs by the agent session that spawned them) are folded into the local port instead of waiting for that PR. Rationale: v2 has no agent-facing PTY tools and no plugin `pty` domain, so a local `bun-pty`-backed implementation is the only route; owning it removes a version-sensitive third-party dependency from the harness, lets the sidebar ship with the tools it is a window onto, and keeps the v1 harness's existing npm dependency untouched. The v1 `pty-monitor` source stays as the behavioural reference for the port.
