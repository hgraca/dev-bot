---
date: 2026-06-14
keywords: ["devbot", "external-modules", "skills"]
---

## Verify external skill paths exist in vendor repos before declaring

The `svelte-explicit` skill declared in external-modules.json pointed to `anthropics/skills/skills/svelte-explicit` but the cloned repo had no svelte skills at all — its skills/ directory contained only design/doc/slide skills. Before adding an entry to external-modules.json, check the cloned vendor repo's directory structure exists by reading the actual SKILL.md at the target path. A broken path in external-modules.json means silent failure during devbot init wiring — the symlink simply never gets created.
