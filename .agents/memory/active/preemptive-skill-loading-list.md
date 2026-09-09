---
tags: [bootstrap, session, skills]
description: Context skills to preemptively load — dev-bot repo: opencode harness config authoring, docs site, git-commit discipline, make runner
---

## Preemptive Context Skill Loading

The agent must preemptively load the following context skills at the start of every session:

- `devbot:software-development` — generic craft hub: code-quality principles, tests-first discipline, and the commit protocol (incl. `.py` parse gate, CLI failure prefixes); carries the preemptive loading of `devbot:make-tests` + `test-driven-development`.
- `devbot:git-conventional-commits` — Conventional Commits format; repo history is strictly conventional and atomic, so every commit message depends on it.
- `devbot:git-atomic-commits` — one logical change per commit with `git add` of specific files only; the repo forbids catch-all commits.
- `devbot:git-advanced-operations` — partial staging and history surgery for separating unrelated edits (common when doc/memory files pile up next to code).
- `devbot:git-fixup-commits` — correcting an earlier commit on the branch instead of adding fixup noise.
- `customize-opencode` — this repo authors opencode/claudecode agents, skills, tools, plugins, hooks, and harness config under `src/agentic/`, `src/harnesses/`, and `.agents/`; any edit there must respect harness conventions and runtime wiring.
- `devbot:makefile` — `make` is the preferred runner (`make test`, `make install`, `make up`, `make docs`); the Makefile wraps lifecycle scripts and the full test suite.
- `devbot:documentation-rules` — `docs/` is a Jekyll site with hand-synced reference tables (module-reference, mcps, hooks); writing or editing docs must follow its conventions.
