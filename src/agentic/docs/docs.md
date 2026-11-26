---
title: "Docs"
description: "Documentation tooling — the module-docs generator, documentation rules, and architecture maps."
skills: ["app-map", "documentation-rules", "impact-diagram", "use-case-map"]
tools: ["assert-pages-build-type", "gather-module-docs", "impact-diagram", "use-case-map"]
---

How dev-bot's own documentation is written, gathered and published — plus the diagram tooling for mapping an application.

## What it does

- **`gather-module-docs`** — the build-time generator behind this site. It walks `src/<area>/<module>/docs.md`, derives each module's capability manifest from its own files, and emits one page per module plus the `/modules` index and the navigation data. See [Create a module](/create-a-module).
- **`assert-pages-build-type`** — the deploy workflow's preflight. It fails the build when GitHub Pages would serve the branch instead of the artifact this workflow uploads.
- **`documentation-rules`** — where docs live, how they are structured, and the README table of contents invariant.
- **`use-case-map`** — traces call chains from entry points through commands, handlers, ports and adapters in a PHP codebase.
- **`impact-diagram`** — the diff-scoped use-case map: only the flows a change touches, changed units in red.
- **`app-map`** — the editor for drawing architecture diagrams: an interactive map saved as JSON and exported as SVG.

## Configuration

The site is a static Jekyll build under `docs/`. `make docs` runs the gather before serving; the GitHub Pages workflow runs it before `jekyll build`.

Publishing must be set to **GitHub Actions** (`build_type: workflow`). A branch (`legacy`) source serves the committed `docs/` folder alone, so every generated page and `install.sh` 404s. The deploy workflow fails when the source is anything else, saying how to switch it.

## See also

- [Polyrepo sessions](/polyrepo-sessions) — how this module scopes itself to the owning project
- [Create a module](/create-a-module) — how to document a module
- [Module Reference](/module-reference) — module anatomy
