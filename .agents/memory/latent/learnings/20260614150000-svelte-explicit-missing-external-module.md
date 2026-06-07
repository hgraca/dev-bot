---
date: 2026-06-14
keywords: ["svelte", "external-modules", "svelte-explicit", "anthropics", "gotcha"]
---

## svelte-explicit declared in external-modules.json but vendor repo has no svelte skills

`src/agentic/svelte/external-modules.json` declares `svelte-explicit` from `github.com/anthropics/skills` at path `skills/svelte-explicit` (line 8–13), but the cloned vendor at `vendor/anthropics/skills/skills/` contains 18 non-svelte skills (algorithmic-art, brand-guidelines, etc.) and zero svelte-related content. No symlink was created for it. The external module declaration is broken — the referenced path does not exist in the upstream repo. Either the skill was removed from anthropics/skills, was renamed, or the URL is wrong. The other three declared external modules (mindrally-svelte, sveltekit-structure, svelte5-best-practices) were all verified to exist and are symlinked into `.opencode/skills/`.
