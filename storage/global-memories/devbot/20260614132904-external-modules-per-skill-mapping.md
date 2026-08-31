---
date: 2026-06-14
keywords: ["devbot", "external-modules", "skills", "mapping"]
---

## external-modules.json maps individual skill dirs, not just whole repos

external-modules.json entries can map individual skill subdirectories from a repo, not only top-level paths. Use paths like `{"svelte": "skills/svelte"}` to map a specific directory inside the cloned repo to a destination under `.opencode/`. This allows wiring a single skill from a large multi-skill repo (e.g. mindrally/skills) without pulling in unrelated skills. Each entry becomes its own module in `.devbot.jsonc` after bin/up.sh merges it.
