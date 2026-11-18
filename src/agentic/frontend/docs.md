---
title: "Frontend"
description: "Framework-agnostic frontend conventions — atomic design, design tokens, Storybook, a Figma-to-app Design QA check, and the vendored design skills (aesthetic direction, critique, motion) — shared by every UI framework module."
commands: ["design-qa", "design-qa-all"]
skills: ["atomic-design", "design-system", "storybook", "design-qa", "design-qa-all", "show-ui-in-browser"]
hooks: ["impeccable-detector"]
mcps:
  figma: "Read Figma frames, variables and screenshots"
---

Frontend conventions that are independent of any one UI framework. A framework module (React,
Svelte, …) adds the framework-specific conventions; this module supplies the structure they share,
plus an automated Design QA check that compares a running page against its Figma frame.

## What it does

- **`design-system`** — creating or extending the system: the token contract as data, three layers of
  token (primitive → semantic → component), light and dark as mappings rather than two designs, theme
  variants, and a WCAG AA contrast gate that fails a build. See
  [Design system ownership](#design-system-ownership).
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
- **`impeccable-detector`** (hook) — run Impeccable's design detector over each UI file the agent
  edits, and log the findings. See [Design detector hook](#design-detector-hook).
- **`modern-web-guidance`** (vendored) — Google's
  [modern-web-guidance](https://github.com/GoogleChrome/modern-web-guidance) skill pack, wired in
  when the module is enabled; it adds modern web-platform guidance (HTML, CSS, accessibility,
  performance) through its own CLI.

## Design system ownership

Three capabilities touch "design system", and the split is deliberate — a request must route to
exactly one of them:

| Request                                                                                                                  | Owner                             |
| ------------------------------------------------------------------------------------------------------------------------ | --------------------------------- |
| Create or extend the token system: contract, semantic CSS variables, light/dark, theme variants, contrast floors, scales | `devbot:design-system`            |
| Where a component lives and what it may import (atoms → pages)                                                           | `devbot:atomic-design`            |
| Harvest tokens out of an interface that already exists, or write `DESIGN.md`                                             | impeccable `extract` / `document` |

Each dev-bot skill's description opens with its trigger rather than burying it in a trailing list —
that is what failed before: `atomic-design` ended with "design tokens" behind an atoms-and-molecules
opening, `impeccable` mentioned "capturing or documenting design systems" late in a long verb list,
and **no** skill owned the from-scratch contract, so a session that asked for one loaded nothing and
hand-built the pipeline. `skills/*/evals/evals.json` now pins the routing: each eval names the skill
that must fire plus the literal trigger phrases, and `frontend_tests.bats` fails when a phrase is
claimed by two descriptions or by none.

The vendored descriptions are upstream-owned (the clone is read-only), so the boundary is held on
our side: `design-system` names the harvest/extract case as impeccable's, and `atomic-design` hands
token work to `design-system`.

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

## Design detector hook

Enabling this module also wires Impeccable's rule-based design detector to every UI edit. `devbot
init` seeds `.impeccable/config.json`:

```json
{
  "hook": {
    "enabled": true,
    "limits": { "maxFindings": 5, "maxChars": 8000 }
  }
}
```

and the module's own `file.edited` hook (`impeccable-detector` → `tools/impeccable-hook.sh`) runs
`impeccable detect` on the file the agent just wrote, on both harnesses. Two things it catches that a
palette grep does not: an off-ramp radius (`rounded-[2px]` against a documented radius scale) and
arbitrary font sizes in product mocks (`text-[13px]` where nothing else on the page leaves the type
ramp). Findings land in `.agents/logs/impeccable.log`, capped by the `limits` above.

**Where the findings go.** The hook declares `surface: "tool-result"`, so on OpenCode — v1 and v2
alike — its stdout is appended to the **tool result of the edit that triggered it**. The agent reads
the finding in the same turn, which is what Claude Code and Codex get from their post-tool-use hook;
dev-bot reaches it by running the hook from the tool hook, where the result is still mutable. Claude
Code has no such seam in this toolkit (its dispatcher writes hooks to a log and drops stdout), so
there the detector keeps running and its findings reach `.agents/logs/impeccable.log` only. Every run
keeps the log either way: it is the audit trail, the appended text is what changes behaviour.

**Why dev-bot dispatches it instead of `impeccable hooks on`.** That command installs a harness
manifest for Claude Code, Codex, Cursor, Copilot, Grok or Gemini — not opencode, this toolkit's
primary harness — and it looks for the project skill under `.claude/skills`, `.cursor/skills` and
friends, while dev-bot links skills into `<devbot_dir>/skills` and flattens only `SKILL.md` into
`.claude/skills`. In a dev-bot project it therefore reports "No design harness is wired", and its
`.agents` provider is Codex's repo-skills folder: running it here would write a `.codex/hooks.json`
for a harness the project does not use. The module owns the dispatch instead, so the same config file
is the one switch both the CLI and the hook read.

**Scope.** Markup and style files only: `.tsx`, `.jsx`, `.html`, `.vue`, `.svelte`, `.astro`, `.css`,
`.scss`, `.sass`, `.less`. Plain `.ts`/`.js` are deliberately excluded — impeccable scans those only in
a project carrying `PRODUCT.md`, `DESIGN.md` or `.impeccable/`, which is every project with this
module, and running the engine on every TypeScript edit is not worth it. `impeccable detect --changed`
covers them on demand. File scans are regex-based; element rules (contrast, tiny text) run only on a
rendered page, so this is an undercount, not a clean bill of health.

**Cost.** The engine downloads once (~25 MB, into `~/.impeccable/bin/`) on the first UI edit, then
runs per edit. It works with the agent's network access and is not sandboxed. A clean file is silent;
only findings are logged.

**Off, and consent.** `impeccable hooks off` writes `hook.enabled: false` and the hook stops;
`IMPECCABLE_HOOK_DISABLED=1` covers one shell. `devbot init` never rewrites an existing
`.impeccable/config.json`, so an off project stays off across reinits. The detector is a review
convenience, not a quality gate — the same checks run on demand with
`impeccable detect --json --changed`. The machine-local `.impeccable/config.local.json` (what the
upstream installer records per machine) is never written by dev-bot and is added to `.gitignore`, so
it cannot be committed; a project opts in through the module and this committed config, and opts out
by turning the hook off.

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
