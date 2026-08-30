---
date: 2026-06-13
keywords: ["devbot", "remember-checkpoint", "skill-removal"]
---

## remember-checkpoint skill removed

Deleted `src/agentic/memory/skills/remember-checkpoint/SKILL.md` per stakeholder request. Removed references from 3 agent files: `devbot.md`, `developer.md`, `architect.md`. Each had a line `- When context nears limit or opencode triggers compaction, use \`remember-checkpoint\``.

The `remember-checkpoint` skill was already functionally obsolete — its purpose (saving context before compaction) is handled automatically by the `remember-session` plugin which captures on post-commit and the `remember-session` plugin hooks.

The symlink at `.opencode/skills/devbot/memory/remember-checkpoint/` auto-disappeared since it pointed into the deleted directory through the `memory/` → `src/agentic/memory/skills/` symlink.
