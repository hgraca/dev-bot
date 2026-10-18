---
title: "Frontend"
description: "Framework-agnostic frontend conventions — atomic design, design tokens, Storybook, and a Figma-to-app Design QA check — shared by every UI framework module."
commands: ["design-qa", "design-qa-all"]
skills: ["atomic-design", "storybook", "design-qa", "design-qa-all"]
mcps:
  figma: "Read Figma frames, variables and screenshots"
---

Frontend conventions that are independent of any one UI framework. A framework module (React,
Svelte, …) adds the framework-specific conventions; this module supplies the structure they share,
plus an automated Design QA check that compares a running page against its Figma frame.

## What it does

- **`atomic-design`** — the five-tier component structure (atoms → molecules → organisms →
  templates → pages), the component folder layout with colocated test/story/barrel, where the
  generated primitives and the design-token stylesheet live, and worked examples in both React and
  Svelte.
- **`storybook`** — building a Storybook as a static site, wiring it into a static documentation
  site (landing page, generated component list, deep links into the stories), and publishing it to a
  host; the GitHub Pages deployment lives in a loadable annex, so other hosts are added without
  changing the core.
- **`design-qa`** — compare one Figma frame against a page or section in a real browser and report
  differences ranked by severity, each mapped to `file:line`; optional `--fix` for High and Medium
  issues.
- **`design-qa-all`** — run the same check for every entry in the project's `design-map.json`, only
  the entries a branch changed, or a single entry, and write `design-qa-report.md`. Report-only: it
  never edits source.
- **`modern-web-guidance`** (vendored) — Google's
  [modern-web-guidance](https://github.com/GoogleChrome/modern-web-guidance) skill pack, wired in
  when the module is enabled; it adds modern web-platform guidance (HTML, CSS, accessibility,
  performance) through its own CLI.

## Design QA

Both commands need two MCP servers: `figma` (declared by this module, shipped **wired but not
started**) and `playwright` (the `playwright` module, also shipped not started). Enable both, and
authenticate Figma interactively (`/mcp` → figma → Authenticate).

The check never logs in or handles credentials. Log in by hand, once per user type, in the browser
window Playwright opens; its profile keeps the session between runs. Reset that browser's per-site
zoom to 100% (Cmd+0 / Ctrl+0) — widths and positions are measured in CSS px.

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
  "defaults": { "viewports": [1440], "tolerancePx": 4, "userType": "backoffice" },
  "project": {
    "userTypes": ["backoffice", "customer", "hotel", "public"],
    "session": {
      "storage": "localStorage",
      "key": "user",
      "detect": { "backoffice": "u.isBackoffice === true", "customer": "Boolean(u.customer)" }
    },
    "publicRoutes": ["/sign-in", "/forgot-password"],
    "sourceRoot": "src/",
    "sharedRoots": ["src/components/", "src/layouts/"],
    "globalStyleFiles": ["src/theme.ts", "src/index.css"],
    "stabilise": { "hideSelectors": ["#third-party-launcher"] },
    "tokens": {
      "colors": { "file": "src/constants/colors.ts", "name": "COLORS", "style": "UPPER_SNAKE_CASE" },
      "theme": { "file": "src/theme.ts" },
      "spacing": "mui-8px",
      "layout": ["TOOLBAR_HEIGHT"]
    },
    "lint": { "lint": "pnpm lint", "format": "pnpm prettier:check" },
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

`entries[]` requires `id`, `type` (`page` or `component`), `figma` and `url`; `userType`, `state`,
`scope`, `viewports`, `sourcePaths` and `ignore` are optional. A `url` that still carries a route
parameter (`:id`) is skipped by the batch, because it needs a concrete record that matches the state
the frame shows.

When the file or a field is absent the workflow falls back to `http://localhost:3000`, a ±4px
tolerance and a 1440px viewport; the `project` block has no fallbacks beyond that, so an unconfigured
project simply skips the features it does not declare (token checks, lint, shared-root selection).

## Configuration

Enable the module. `design-qa` additionally needs the `playwright` module enabled and the Figma MCP
authenticated; the figma server ships `enabled: false`, so opt the module in and turn the server on in
the harness (opencode: `mcp.figma.enabled: true` in `opencode.jsonc`; on Claude Code, enabling the
module wires it). No OS packages are installed — both servers are remote or MCP-managed.

## See also

- [React](/modules/agentic/react) — the React and Next.js framework module
- [Svelte](/modules/agentic/svelte) — the Svelte and SvelteKit framework module
- [Playwright](/modules/agentic/playwright) — the browser MCP the checks drive
- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
