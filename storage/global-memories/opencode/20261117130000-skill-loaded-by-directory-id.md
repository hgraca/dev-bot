---
date: 2026-11-17
keywords: ["opencode", "skill-tool", "skill-id", "frontmatter"]
aliases: ["Unable to load skill", "devbot: prefix fails", "skill advertised id"]
supersedes: ["devbot/20261117115500-skill-tool-fails-to-load-existing-skills.md"]
---

## A skill loads by its directory id, not by its frontmatter name

The `skill` tool resolves the **path-derived id** — the skill's directory name, `reconcile-work` —
and frontmatter `name:` is display-only; the tool does not accept the name. Our instruction docs
write skills as `devbot:<skill>` (867 references), following the display name, so an agent that
obeys them calls an id that cannot resolve and gets `Unable to load skill devbot:<skill>`.

Verified against the running server: `GET /api/skill?location[directory]=<project>` returns
`{id: "reconcile-work", name: "devbot:reconcile-work", path: ".../reconcile-work/SKILL.md"}`, and the
advertised block renders `<id>${skill.id}</id>` (`packages/core/src/skill/instructions.ts`), i.e. the
bare id. An earlier version of this note blamed the advertisement for printing the display name as the
id — that was wrong, and an upstream report built on it (anomalyco/opencode#64427) was closed as
not-a-bug. Nothing in discovery or loading is mismatched.

Invoke skills by the bare directory name. A name fallback in the skill tool is proposed upstream
(anomalyco/opencode#64434) as a convenience; it is not in the released build, and it deliberately
leaves `Skill.get` alone so `skill://` URIs and `files()` keep working.
