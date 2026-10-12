---
date: 2026-10-12
keywords: ["frontend", "storybook", "deploy", "skill", "annex", "github-pages"]
see: ["ADRs/20260823111100-software-development-hub-skill-annexes.md", "ADRs/20261012143000-frontend-module-atomic-design-extraction.md"]
---

## Storybook deployment lives in a frontend skill whose per-host steps are annexes

Publishing a Storybook is a host-independent build plus a host-specific publish, and the hosts will multiply (GitHub Pages first; Netlify, S3, Vercel, Chromatic later). Rather than one skill per host, a single `devbot:storybook-deploy` skill in the `frontend` module (`src/agentic/frontend/skills/storybook-deploy/`) owns the generic half — the `build-storybook` flow, the target-agnostic rules, and a target-selection table — and each host is a plain reference file under `annexes/` (`annexes/github-pages.md` for now) read only when that target is chosen. Adding a host is a new annex plus one row in the table; the core never changes, and no host's specifics load into a session that is not deploying to it. This is the hub-skill-plus-annexes pattern chosen for `devbot:software-development` (ADR 20260823111100), applied here with the **deploy target** as the annex axis instead of the language/framework; annexes remain plain files read on demand, not loadable skills.
