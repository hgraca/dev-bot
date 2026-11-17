---
title: "Frontend"
description: "Framework-agnostic frontend conventions — atomic design, design tokens, Storybook, a Figma-to-app Design QA check, and the vendored design skills (aesthetic direction, critique, motion) — shared by every UI framework module."
commands: ["design-qa", "design-qa-all"]
skills: ["atomic-design", "storybook", "design-qa", "design-qa-all", "show-ui-in-browser"]
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
- **`show-ui-in-browser`** — get the app answering at a URL and leave a visible browser window on the
  page the user asked for, including the login step and the check that it actually rendered.
- **`modern-web-guidance`** (vendored) — Google's
  [modern-web-guidance](https://github.com/GoogleChrome/modern-web-guidance) skill pack, wired in
  when the module is enabled; it adds modern web-platform guidance (HTML, CSS, accessibility,
  performance) through its own CLI.

## Design skills (vendored)

Three external skill packs cover the design loop — aesthetic direction, review, and motion — and are
wired in by `devbot init` when the module is enabled. They are declared in `external-modules.json`
and cloned into `vendor/`; nothing is copied into this repository.

- **Baseline — `anthropic-frontend-design`**, from
  [anthropics/skills](https://github.com/anthropics/skills): aesthetic direction, typography and
  palette choices that do not read as templated defaults, when building new UI or reshaping an
  existing one.
- **Review/QA — `impeccable`**, from [pbakaus/impeccable](https://github.com/pbakaus/impeccable):
  `critique` (a scored UX review) and `audit` (accessibility, performance, theming, responsive
  behaviour), plus `polish`, `harden`, `typeset`, `layout` and a rule-based slop detector. Ask for
  `critique` on a section that already exists; it is strongest on interfaces you can point it at.
- **Motion/polish — `emil-*`**, from
  [emilkowalski/skills](https://github.com/emilkowalski/skills), wired as four skills:
  `emil-design-eng` (the philosophy), `animate` (build one), `review-animations` (hold it to the
  bar) and `improve-animations` (audit a codebase and plan the fixes).

Only these four are wired on purpose. Every vendored skill description is always-on session context,
and the rest of that repository — `choreograph`, `gestures`, `apple-design`,
`find-animation-opportunities`, `remove-animations`, `animation-performance`,
`animation-vocabulary`, plus the Expo/Swift/native packs — either overlaps these four or does not
apply to a web project. The files are all present in the clone, so a skill's own references (e.g.
`review-animations` → `../choreograph/SKILL.md`) still resolve; wire one permanently with
`devbot module add` when a project leans on it.

Every entry maps a whole skill directory, so the skill keeps its own `SKILL.md`, references and
helper scripts; the config key becomes the link name under `.agents/skills/`. Impeccable ships its
launcher inside the skill, so there is no global install: its `Setup` step runs
`<skill-base-dir>/scripts/impeccable context` from wherever the skill is linked, and the binary is
fetched once on first use.

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
  claude mcp add --scope user playwright -- npx @playwright/mcp@latest --browser chromium
  ```

  The second command registers Playwright directly; it bypasses the module's Docker-preferring
  wrapper deliberately (see the browser note below).

Then authenticate Figma (`/mcp` → figma → Authenticate).

**Browser window and login.** The Playwright module's launcher prefers Docker when a daemon is
available, and that path exposes neither a browser UI nor a persistent profile — so manual login
cannot work through it. For authenticated QA, run Playwright locally (it is headed by default) with a persistent
profile, e.g. `npx @playwright/mcp@latest --browser chromium --user-data-dir
~/.cache/dev-bot/playwright-profile`, and register that command as the server (the Claude Code form
above does this; for opencode, point the `playwright` entry's `command` at it). The profile keeps the
session between runs.

Prerequisites:

- The app is running at `baseUrl` — the batch preflight checks it.
- `design-map.json` exists at the project root (both commands read it).
- A human logs in to the app, once per user type, in the browser window Playwright opens; its profile
  keeps the session between runs. The check never logs in and never handles credentials.
- Reset that browser's per-site zoom to 100% (Cmd+0 / Ctrl+0) — widths and positions are measured in
  CSS px.
- Ignore `.playwright-mcp/` and `design-qa-report.md`: the report can contain authenticated-app data
  (names, amounts, statuses), and the Playwright directory holds screenshots and console logs.

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

Enable the module, then turn on the two servers as described under [Design QA](#design-qa): the figma
server ships `enabled: false`, and the `playwright` module does the same. No OS packages are installed
— both servers are remote or MCP-managed.

## See also

- [React](/modules/agentic/react) — the React and Next.js framework module
- [Svelte](/modules/agentic/svelte) — the Svelte and SvelteKit framework module
- [Playwright](/modules/agentic/playwright) — the browser MCP the checks drive
- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
