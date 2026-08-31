---
date: 2026-06-14
keywords: ["devbot", "svelte", "skills", "contradictions"]
---

## Check external skill repos for contradictions when adding module skills

When a devbot module declares external skills via external-modules.json, verify those skills exist in their cloned vendor repos before declaring them. Use explore subagent to find and read all SKILL.md files from the vendored repos, then cross-reference their guidance against the module's own SKILL.md. Common contradiction sources: Svelte 4 vs 5 syntax (on:click vs onclick), competing UI component library recommendations (SMUI vs Bits UI vs Melt UI), and deprecated patterns (createEventDispatcher vs callback props, slots vs snippets).
