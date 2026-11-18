---
title: "Frontend"
description: "Framework-agnostic frontend conventions — atomic design, design tokens, Storybook, and the vendored design skills (aesthetic direction, critique, motion) — shared by every UI framework module."
skills: ["atomic-design", "design-system", "storybook", "show-ui-in-browser"]
hooks: ["impeccable-detector"]
---

Frontend conventions that are independent of any one UI framework. A framework module (React,
Svelte, …) adds the framework-specific conventions; this module supplies the structure they share.
Comparing a running page against its Figma frame lives in the [Figma](/modules/agentic/figma) module.

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

## Configuration

Enable the module; init seeds the design detector's config (see
[Design detector hook](#design-detector-hook)). No OS packages are installed and no server is wired —
the Figma frame comparison, and the MCP servers it drives, live in the
[Figma](/modules/agentic/figma) module.

## See also

- [React](/modules/agentic/react) — the React and Next.js framework module
- [Svelte](/modules/agentic/svelte) — the Svelte and SvelteKit framework module
- [Figma](/modules/agentic/figma) — the Design QA check against a Figma frame
- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
