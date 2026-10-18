---
date: 2026-10-18
keywords: ["preemptive", "skills", "memory", "session-start"]
aliases: ["preemptive skill loading list", "skills manifest", "preemptive context skills"]
---

## Retire the preemptive skill loading list

The session-start skills manifest (`.agents/memory/active/preemptive-skill-loading-list.md`) is retired: the memory template no longer scaffolds it, `devbot:create-project-report` no longer authors it, and `devbot.md` no longer tells the agent to load the skills it lists. The file was never parsed by code — it was a Markdown convention loaded by the opencode `instructions` glob — and its maintenance cost (per-project authoring, staleness, always-on context) outweighed the pre-warm. `devbot init` and `reinit` now delete any leftover copy, including the legacy misnamed `preemptive-skill-loading.md` (audit-21), from `_scaffold_vault`. The preemptive-loading rule hardcoded in `devbot:software-development` (load `devbot:git-commits` on first load) is a separate mechanism and is unaffected, as is the `create-skill` description convention for preemptively-loaded skills.
