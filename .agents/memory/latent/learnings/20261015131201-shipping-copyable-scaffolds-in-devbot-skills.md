---
date: 2026-10-15
keywords: ["devbot", "skill", "assets", "template", "scaffold"]
aliases: ["skill template tree", "copyable scaffold in a skill"]
---

# Shipping a copyable scaffold inside a dev-bot skill

## Where it goes, and the two conventions

Reference prose goes in `annexes/`, read on a trigger (`frontend/skills/storybook`, `dev/skills/software-development`). Copyable files go in `assets/` (`dev/skills/makefile`, `docs/skills/app-map`, `k8s/skills/lint-k8s`). A scaffold the user copies into their own repo belongs in `assets/` and should **mirror the target repo layout exactly** — including `.github/workflows/` and `.gitignore` — so the copy is mechanical and the destination is obvious from the path. Each scaffold carries a `README.md` with a "what goes where" table and a placeholder table.

## What is inert, and what is not

- **The docs generator is safe.** `src/agentic/docs/tools/gather-module-docs.py` globs non-recursively (`skills/*/SKILL.md`, `agents/*.md`, `commands/*.md`), so arbitrary files under `assets/` — a template `README.md`, `index.md` — produce no module page and no aggregate row. A template must never contain a `SKILL.md`, or the generator would read it as a second skill.
- **BATS is safe.** `bats -r src/` collects only `*.bats`.
- **`bun test src/` is NOT inert.** It discovers `.test.mjs` recursively, so a template's `node:test` suite becomes part of `make test`. That is a feature only if the suite passes standalone — verify with `bun test <template dir>` first.
- **A shipped `.gitignore` is live** for the subtree it lands in, and can silently hide a file you just copied; run `git check-ignore -v` on every non-obvious path before `git add`.
- **The claudecode harness flattens only `SKILL.md`** into `.claude/skills/`, while the opencode farm symlinks the whole skill directory. Anything mandatory must be inline in `SKILL.md`; `annexes/` and `assets/` are opencode-reachable only.

## Placeholders

Prose, config and URIs use angle-bracket placeholders (`<org>`, `<repo>`, `<Project Name>`) — unmistakable as placeholders and safe inside fenced code, YAML and JSON bodies. Where a value must stay syntactically valid, use a word instead (the umbrella generator defaults its org to `your-org`, because a JavaScript string cannot carry `<org>`). Never leave the convention undocumented: state it in the annex/SKILL and in each template's placeholder table.

## Brand and org-specific assets

Never ship a real organisation's logos or favicon in a generic skill — replace them with neutral placeholder SVGs (a plain mark keeps the light/dark swap working) and tell the user to swap them in. Genericise every org identifier and audit mechanically before committing (`rg -ni '<org>|<product>' <skill dir>`); a single leaked internal repo name survived into a worked example and was caught only by review.
