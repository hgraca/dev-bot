---
date: 2026-11-27
keywords: ["mcp", "playwright", "roots", "streamable-http", "docker"]
aliases: ["playwright mcp gateway", "per-client workspace root", "mcp roots isolation"]
trigger-on: ["playwright-mcp-http-gateway", "mcp-roots-workspace"]
---

## One Playwright MCP container can serve many projects, because `roots` is the session's cwd

Playwright MCP's streamable-HTTP mode (`--port`, endpoint `/mcp`) is multi-client: each HTTP
client gets its own browser context, and the server asks every client for its MCP `roots` and uses
the **first root as that session's working directory**. So a single machine-wide container gives
each project its own workspace root — the isolation the per-session `docker run -v "$PWD:$PWD"
-w "$PWD"` used to provide. The server code is
`capabilities?.roots && !ignoreRoots → listRoots() → cwd = firstRootPath(roots)`, and `checkFile`
then confines writes to `outputDir ∪ cwd`.

Four traps, each verified against v0.0.86:

- **The Docker catalog image is stale.** `mcp/playwright:latest` is v0.0.76 (built 2026-06) and
  predates roots entirely — no `--ignore-roots`, no roots request, every session falls back to
  `process.cwd()`. Use `mcr.microsoft.com/playwright/mcp:vX.Y.Z` (MCR publishes tags) instead.
- **`--allowed-hosts` compares the Host header including its port**, so a published mapping needs
  `127.0.0.1:18505` (listing the bare IP still 403s every request).
- **A client that declares no roots gets the container's cwd.** Point `working_dir:` at the mounted
  root, or a roots-less client's relative writes land in the container layer (`/home/node`) and
  never reach the host.
- **The healthcheck must DELETE the session it opens.** `initialize` returns an `Mcp-Session-Id`
  that the server retains (stateful: one browser context each) until `DELETE /mcp` with that
  header. A 30-second probe that only initialises leaks a browser per probe for the container's
  whole life.

`file:` navigation stays blocked unless `--allow-unrestricted-file-access`, in every mode; serve a
local UI over `http://127.0.0.1:<port>` instead.
