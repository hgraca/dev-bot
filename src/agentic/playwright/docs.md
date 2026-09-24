---
title: "Playwright"
description: "Drive a real browser from an agent — end-to-end testing and UI reproduction."
mcps:
  playwright: "Browser automation and end-to-end testing"
---

Drive a real browser: navigate, interact, and assert — for end-to-end tests, or to reproduce a UI bug the way a user hits it.

## What it does

Wires the Playwright MCP server (`mcp/playwright`) into the harness.

Launch is **hybrid**: where Docker is available it runs the server in a container (`docker run --rm -i --label dev-bot.mcp=playwright`), and otherwise it falls back to a locally installed `@playwright/mcp`. The local binary is resolved by explicit npm-prefix paths rather than the bare name on `PATH`, so a stale system binary can never win.

## Configuration

`install.sh` installs the pinned `@playwright/mcp` version recorded in `versions.env`; `devbot update` resolves the newest version and rewrites the pin. Registered on `devbot init` when the module is enabled. If the package is missing, the launch fails loudly with `FATAL: @playwright/mcp not installed — run 'devbot install' (module playwright)`.

## See also

- [Chrome DevTools](/modules/agentic/chrome-devtools) — the inspection sibling
- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
