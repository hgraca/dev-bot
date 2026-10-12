---
date: 2026-10-12
keywords: ["frontend", "atomic-design", "module", "skills"]
aliases: ["atomic design module", "frontend conventions module", "explicit-react rename"]
see: ["ADRs/20261012133356-frontend-storybook-deploy-target-annexes.md"]
---

## Atomic design lives in a framework-agnostic `frontend` module, opt-in rather than wired

The react and svelte skills each carried their own copy of Brad Frost's atomic design, and the two had drifted (svelte had a `pages` tier, react did not). The instructions now live once, in a new framework-agnostic module `src/agentic/frontend/` as the `atomic-design` skill: all five tiers (atoms → molecules → organisms → templates → pages), a framework-neutral folder layout, and worked examples in both React and Svelte. The framework skills keep only framework-specific conventions — every atomic-design mention (the normative section, the intro bullet, the roadmap step, and the tier folders in their project trees) was stripped, so a third UI framework can reuse the shared skill without a third copy.

Two decisions accompany the extraction. First, **the modules are deliberately unlinked**: dev-bot has no inter-module dependency mechanism, and none was added — a project opts into the shared skill by naming it in its `memory project.md`. This keeps the framework modules and `frontend` independently enable/disable-able, at the cost that enabling `react` does not auto-enable `frontend`. Second, the framework skills were **renamed** `explicit-react → react` and `explicit-svelte → svelte` (frontmatter `devbot:react` / `devbot:svelte`). The `explicit-` prefix was dropped as opaque, accepting that `devbot:react` now coexists in the palette with the vendored mindrally skill literally named `react` — checked for a concrete defect (none: the `devbot:` namespace separates them, claudecode flattens by raw name to distinct dirs, and there is no farm collision). `frontend` ships disabled by default, like every other optional framework module.
