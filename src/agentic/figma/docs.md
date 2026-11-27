---
title: "Figma"
description: "Compare a Figma frame with the running implementation — a severity-ranked design QA check mapped to file:line, and a batch mode over design-map.json."
commands: ["design-qa", "design-qa-all"]
skills: ["design-qa", "design-qa-all"]
mcps:
  figma: "Read Figma frames, variables and screenshots"
---

A design QA loop that starts at a Figma frame and ends at `file:line`: fetch the frame, open the page
in a real browser, measure the rendered element by element, and report the differences that matter.

## What it does

- **`design-qa`** — compare one Figma frame against a page or section in a real browser and report
  differences ranked by severity, each mapped to `file:line`; optional `--fix` for High and Medium
  issues.
- **`design-qa-all`** — run the same check for every entry in the project's `design-map.json`, only
  the entries a branch changed, or a single entry, and write `design-qa-report.md`. Report-only: it
  never edits source.
- **`figma`** (MCP) — read a frame's metadata, design context, variables and screenshot; declared
  here and shipped **wired but not started**.

## Design QA

Both commands need two MCP servers: `figma` (declared by this module) and `playwright` (the
`playwright` module). Both ship **wired but not started** — `enabled: false` — because they are heavy
or optional. How to turn them on depends on the harness:

- **opencode** — the servers are registered with `mcp.<name>.enabled: false`. Set both to `true` in the
  project's `opencode.jsonc` and restart; opencode reads its config once at startup.
- **Claude Code** — `.mcp.json` has no per-server switch, so a server declared `enabled: false` is
  **omitted** from it (and regenerated without it). Register both servers in Claude Code's own user
  config instead:

  ```bash
  claude mcp add --transport http --scope user figma https://mcp.figma.com/mcp
  claude mcp add --scope user playwright -- npx @playwright/mcp@latest --browser chromium --output-dir .agents/state/playwright-mcp
  ```

  The second command registers Playwright directly; it bypasses the module's Docker-preferring
  wrapper deliberately (see the browser note below). The Playwright recipes assume the default
  `devbot_dir` (`.agents`) — in a project that configures another one, substitute
  `<devbot_dir>/state/playwright-mcp`. A Playwright registered without `--output-dir` keeps writing
  `.playwright-mcp/` in the project root until it is registered again.

Then authenticate Figma (`/mcp` → figma → Authenticate).

**Browser window and login.** The playwright module now ships a **shared gateway** —
headless, and `--isolated` (in-memory profile) so that concurrent sessions never
collide — so it exposes neither a browser UI nor a persistent profile, and
manual login cannot work through it. For authenticated QA, run Playwright
locally (it is headed by default) with a persistent profile, and register that
command as the server (the Claude Code form above does this; for opencode, add a
separate stdio entry instead of the gateway `url`):

```bash
claude mcp add --scope user playwright -- bash -c 'exec npx @playwright/mcp@latest --browser chromium --user-data-dir "$HOME/.cache/dev-bot/playwright-profile" --output-dir .agents/state/playwright-mcp'
```

The profile keeps the session between runs. The `bash -c` wrapper is not
decoration: the harness spawns the server as a program rather than through a
shell, so `~` and `$HOME` reach it literally — and the server resolves both
paths with `path.resolve`, which expands no tilde (`@playwright/mcp` 0.0.80).
A tilde path passed to `--user-data-dir` therefore creates a directory
literally named `~` under the working directory.

`--output-dir` is not cosmetic either: left unset, Playwright MCP writes its
automatically named snapshots and screenshots to `./.playwright-mcp` in its
working directory — the project root when the client launches it there — where
they show up as untracked files. Pointing it at
`<devbot_dir>/state/playwright-mcp` moves them into the state directory
`devbot init` already gitignores (default `devbot_dir` is `.agents`); the flag
resolves against that same working directory.

Prerequisites:

- The app is running at `baseUrl` — the batch preflight checks it.
- `design-map.json` exists at the project root (both commands read it).
- A human logs in to the app, once per user type, in the browser window Playwright opens; its profile
  keeps the session between runs. The check never logs in and never handles credentials.
- Reset that browser's per-site zoom to 100% (Cmd+0 / Ctrl+0) — widths and positions are measured in
  CSS px.
- Keep `design-qa-report.md` out of commits: the report can contain authenticated-app data (names,
  amounts, statuses). Automatically named Playwright artifacts go to the gitignored
  `<devbot_dir>/state/playwright-mcp`; one saved with an explicit `filename` still resolves against
  the project root, flag or not.

```text
/devbot:design-qa <figma-link> <route-or-url> [viewport] [--as <userType>] [--scope "<component>"] [--fix]
/devbot:design-qa-all [--changed-only [--base <branch>]] [--only <id>]
```

The frame link must carry `node-id=`. With `--fix`, the check uses the project's tokens, asks before
changing the theme file or a shared component, re-verifies with a screenshot, runs the project's lint
and format commands on the changed files, and never commits.

### `design-map.json`

The project's map of pages and components to Figma frames, at the repo root. Both commands read it.
Per-project facts — base URL, user types, session lookup, stabilisation selectors, token files, lint
commands, shared roots — live in its `project` block; none are baked into the workflow.

```json
{
  "baseUrl": "https://app.example.test",
  "defaults": {
    "viewports": [1440],
    "tolerancePx": 4,
    "userType": "backoffice"
  },
  "project": {
    "userTypes": ["backoffice", "customer", "hotel", "public"],
    "session": {
      "storage": "localStorage",
      "key": "user",
      "detect": {
        "backoffice": "u.isBackoffice === true",
        "hotel": "Boolean(u.hotel)",
        "customer": "Boolean(u.customer)"
      }
    },
    "publicRoutes": ["/sign-in", "/forgot-password"],
    "preflightRoute": "/sign-in",
    "sourceRoot": "src/",
    "sharedRoots": ["src/components/", "src/layouts/"],
    "globalStyleFiles": ["src/theme.ts", "src/index.css"],
    "stabilise": {
      "hideSelectors": ["#third-party-launcher"],
      "skeletonSelectors": [".skeleton"],
      "loadingSelectors": [".spinner"]
    },
    "tokens": {
      "colors": {
        "file": "src/constants/colors.ts",
        "name": "COLORS",
        "style": "UPPER_SNAKE_CASE"
      },
      "theme": { "file": "src/theme.ts" },
      "spacing": "mui-8px",
      "layout": ["TOOLBAR_HEIGHT"],
      "typography": ["h1", "h2", "body1"]
    },
    "lint": {
      "lint": "pnpm exec eslint",
      "format": "pnpm exec prettier --check",
      "stylelint": null
    },
    "baseBranch": "develop"
  },
  "entries": [
    {
      "id": "invoice-with-lines-unassigned",
      "type": "page",
      "figma": "https://www.figma.com/design/<fileKey>/<name>?node-id=3020-38121",
      "url": "/invoices/8/with-lines",
      "userType": "backoffice",
      "state": "Click \"Edit multiple\" in the Unassigned items card",
      "scope": "Unassigned items card",
      "viewports": [1569],
      "sourcePaths": ["src/pages/invoiceWithLines/**"],
      "ignore": ["app sidebar"]
    }
  ]
}
```

`entries[]` requires `id`, `type` (`page` or `component`), `figma` and — for a `page` — `url`; a
`component` without a `url` is skipped by the batch because there is no page to render it on.
`userType`, `state`, `scope`, `viewports`, `sourcePaths` and `ignore` are optional. A `url` that still
carries a route parameter (`:id`) is skipped too, because it needs a concrete record that matches the
state the frame shows.

The `project` fields are commands and selectors, not literals: `lint`/`format` must accept file paths
(the workflow appends the changed files), `baseBranch` names the branch PRs target, and
`preflightRoute` is a route that answers without authentication.

When the file or a field is absent the workflow falls back to `http://localhost:3000`, a ±4px
tolerance, a 1440px viewport and a `src/` source root; `project.userTypes` defaults to `["public"]`.
The rest of the `project` block has no defaults, so an unconfigured project skips what it does not
declare (token checks, lint, shared-root selection, type detection).

## Configuration

Enable the module (it ships disabled in the default `modules` map, like the rest of the opt-in
modules), then turn on the two servers as described under [Design QA](#design-qa): the figma server
ships `enabled: false`, and the `playwright` module does the same. No OS packages are installed — both
servers are remote or MCP-managed.

## See also

- [Frontend](/modules/agentic/frontend) — the tokens and component structure `--fix` should use
- [Playwright](/modules/agentic/playwright) — the browser MCP the checks drive
- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
