---
title: "Docs"
description: "Documentation tooling — the module-docs generator, documentation rules, GitHub Pages, and architecture maps."
skills: ["app-map", "documentation-rules", "gh-docs-website", "use-case-map"]
tools: ["gather-module-docs"]
---

How dev-bot's own documentation is written, gathered and published — plus the diagram tooling for mapping an application.

## What it does

- **`gather-module-docs`** — the build-time generator behind this site. It walks `src/<area>/<module>/docs.md`, derives each module's capability manifest from its own files, and emits one page per module plus the `/modules` index and the navigation data. See [Create a module](/create-a-module).
- **`documentation-rules`** — where docs live, how they are structured, and the README table of contents invariant.
- **`gh-docs-website`** — scaffolding a Jekyll site deployed to GitHub Pages.
- **`use-case-map`** — traces call chains from entry points through commands, handlers, ports and adapters in a PHP codebase.
- **`app-map`** — an interactive application-map editor.

## Configuration

The site is a static Jekyll build under `docs/`. `make docs` runs the gather before serving; the GitHub Pages workflow runs it before `jekyll build`.

## See also

- [Create a module](/create-a-module) — how to document a module
- [Module Reference](/module-reference) — module anatomy
