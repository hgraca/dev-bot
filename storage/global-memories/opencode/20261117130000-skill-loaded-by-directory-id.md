---
date: 2026-11-17
keywords: ["opencode", "skill-tool", "skill-id", "frontmatter"]
aliases: ["Unable to load skill", "devbot: prefix fails", "skill advertised id"]
supersedes: ["devbot/20261117115500-skill-tool-fails-to-load-existing-skills.md"]
---

## A skill loads by its directory id, not by its advertised name

The `skill` tool resolves the **path-derived id** — the skill's directory name, `reconcile-work` —
while frontmatter `name:` is display-only. In this build the available-skills block advertises the
namespaced name (`devbot:reconcile-work`), so calling with the advertised id fails with
`Unable to load skill <id>`, and the bare directory name then loads the same file. Confirmed against
the running server: `GET /api/skill?location[directory]=<project>` returns
`{id: "reconcile-work", name: "devbot:reconcile-work", path: ".../reconcile-work/SKILL.md"}` — the
documented contract is that the path sets the id and `name` is a label. Any skill whose frontmatter
name is namespaced (90 of them in this workspace) is therefore unreachable by the id the model is
told to use; vendor skills hide it because their name matches their directory.

Retry once with the bare directory name before concluding a skill is missing, and only then fall
back to reading `SKILL.md` from `.agents/skills/...` or `src/agentic/...`. The registry is
in-process, not persisted: the DB holds no skill rows, so no reindex fixes this. Upstream report:
anomalyco/opencode#64427.
