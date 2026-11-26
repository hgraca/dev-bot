---
title: "Playwright"
description: "Drive a real browser from an agent — end-to-end testing and UI reproduction."
mcps:
  playwright: "Browser automation and end-to-end testing"
---

Drive a real browser: navigate, interact, and assert — for end-to-end tests, or to reproduce a UI bug the way a user hits it.

## What it does

Runs the Playwright MCP server as a **machine-wide docker compose gateway** —
one container serving every harness instance over streamable-http at
`127.0.0.1:18505/mcp`, instead of one `docker run` per session.

Playwright MCP isolates clients itself, which is what makes a single container
usable by several projects at once:

- **per-client browser state** — every HTTP client gets its own browser context;
  `--shared-browser-context` would share one and is deliberately not used.
- **per-client workspace root** — the server asks each client for its MCP
  `roots` and uses the first as that session's working directory. opencode
  answers with the session's project directory (**verified**), so two agents in
  two repos see two different workspace roots inside the one container. Access
  stays limited to that root: `--allow-unrestricted-file-access` is not used, so
  the guard that makes the declared root a boundary stays armed.
- **a fallback for clients that declare none** — claudecode's roots support is
  **not verified**. A client that sends no roots gets the container's working
  directory, which is set to the mount root for exactly that reason: its files
  still land on the host at a real path, but its access spans the whole mount
  rather than one project. Confirm per client before relying on the smaller
  boundary.
- **`--isolated`** — kept explicit rather than left to the default, so a future
  image that starts writing a profile keyed by workspace root cannot
  reintroduce the collision that breaks two sessions in one repo.

### The mount, and what it grants

`PLAYWRIGHT_ROOT` (the common ancestor of `$HOME` and the registered projects,
derived by `bin/up.sh` exactly as for the codebase-memory gateway) is
bind-mounted at the **same absolute path**, so a client's declared root resolves
unchanged. Exporting `PLAYWRIGHT_ROOT` overrides it, and that value is
**persisted machine-wide** (`playwright_root` in `.devbot.global.jsonc`): the
gateway is one shared container, so a per-invocation root in a single project
would otherwise recreate it under every other project's live sessions. A changed
root, image or working directory is reconciled — the module's `up.sh` recreates
the container when any creation-time property drifts from the compose file,
because Docker fixes all three at creation and `devbot up` runs compose with
`--no-recreate` — and a failed recreation does not count as success: it leaves
the start unrecorded so the next one retries.

Mounting it read-write is a **grant, not a limit**: the chromium process runs as
the host uid with `--no-sandbox` (the image entrypoint hardcodes it), so a
renderer compromise reaches every project under the root plus `~/.ssh`,
`~/.aws`, `~/.config` and the host browser profiles. The MCP `roots` guard
bounds what the **tools** accept, not what the container can read — browsing
untrusted pages is this module's whole purpose, so weigh that before enabling
it. `PLAYWRIGHT_ROOT` is the narrowing control, at the cost of a project outside
it not resolving. codebase-memory mounts the same root read-only because
indexing only reads; a browser must write.

The image runs as uid 1000 — the `node` user — which is the typical developer
uid; on a host with another uid, output and workspace writes fail with `EACCES`.

Automatically named outputs (a screenshot taken without a filename) go to
`storage/playwright`; a **filename given explicitly resolves against the
client's workspace root**, so those land in the project that asked.

`file:` navigation is blocked by default and stays blocked here — the same
behaviour the previous per-session container had. To verify a local UI, serve it
over `http://127.0.0.1:<port>` rather than opening the file.

**No window, no persistent session.** The gateway is headless and isolated, so
authenticated browser work — the manual login `design-qa` performs — cannot run
through it. Register a headed, persistent-profile Playwright under its own
server key for that; `figma/docs.md` carries the recipe.

## Configuration

Ships **disabled** (`playwright: false` in the modules map), like the other heavy
opt-in modules: it pulls a browser image and runs a container. Enabling the
module registers the MCP entry and starts the gateway on the next `devbot up`;
`devbot down` stops it with the rest of the `devbot` compose project. The entry
itself still ships `enabled: false`, so each project opts in explicitly (and the
service only runs where the module is enabled at all).

The image is `mcr.microsoft.com/playwright/mcp:v0.0.86` — Microsoft's, pinned to
the build the behaviour above was verified against (MCR publishes `vX.Y.Z`
tags; moving the pin is a deliberate edit, and `pull_policy: missing` never
re-pulls on its own). The Docker-catalog `mcp/playwright` image is **not**
usable here: its only tag is stale at v0.0.76, which predates per-client
workspace roots, so every session would fall back to a single working directory.

## See also

- [Chrome DevTools](/modules/agentic/chrome-devtools) — the inspection sibling
- [MCP configuration](/mcp-config) — the manifest schema, per-harness wiring, and the port registry
