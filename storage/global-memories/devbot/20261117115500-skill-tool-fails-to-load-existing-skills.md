---
date: 2026-11-17
keywords: ["devbot", "skill-tool", "opencode", "harness"]
aliases: ["Unable to load skill", "skill tool error"]
superseded_by: ["opencode/20261117130000-skill-loaded-by-directory-id.md"]
---

## The `skill` tool fails on skills that load fine from disk

> **Superseded by** `opencode/20261117130000-skill-loaded-by-directory-id.md` (2026-11-17).

`skill("devbot:reconcile-work")` and `skill("devbot:software-development")` both returned
`Unable to load skill <id>` during one session — the first to the primary agent, the second to a
delegated reviewer — while every file involved exists and is served by the symlink farm
(`.agents/skills/devbot/memory/reconcile-work/SKILL.md`, `.../dev/skills/software-development/SKILL.md`).
Other ids in the same session loaded normally, so it is not a global outage and not a permissions
gate. Workaround: read `SKILL.md` from the module path the loader lists (`src/agentic/<module>/...`
or the `.agents/skills/` symlink) and follow it from disk — the instructions are identical. Not yet
root-caused: worth checking the harness skill loader when it recurs, and reporting it as a tool bug
rather than a missing skill.
