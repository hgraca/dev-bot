---
title: "Frontend"
description: "Framework-agnostic frontend conventions — the atomic-design component structure, design tokens, and the Storybook build and publication, shared by every UI framework module."
skills: ["atomic-design", "storybook"]
---

Frontend conventions that are independent of any one UI framework. A framework module (React,
Svelte, …) adds the framework-specific conventions; this module supplies the structure they share.

## What it does

- **`atomic-design`** — the five-tier component structure (atoms → molecules → organisms →
  templates → pages), the component folder layout with colocated test/story/barrel, where the
  generated primitives and the design-token stylesheet live, and worked examples in both React and
  Svelte.
- **`storybook`** — building a Storybook as a static site, wiring it into a static documentation
  site (landing page, generated component list, deep links into the stories), and publishing it to a
  host; the GitHub Pages deployment lives in a loadable annex, so other hosts are added without
  changing the core.
- **`modern-web-guidance`** (vendored) — Google's
  [modern-web-guidance](https://github.com/GoogleChrome/modern-web-guidance) skill pack, wired in
  when the module is enabled; it adds modern web-platform guidance (HTML, CSS, accessibility,
  performance) through its own CLI.

## Configuration

None. Enable the module, then — in a project that wants it — reference the skill from the project's
`memory project.md`.

## See also

- [React](/modules/agentic/react) — the React and Next.js framework module
- [Svelte](/modules/agentic/svelte) — the Svelte and SvelteKit framework module
