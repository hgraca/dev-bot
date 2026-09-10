---
date: 2026-09-10
keywords: ["devbot", "docs", "skills", "documentation"]
---

# docs/skills.md mirrors each SKILL.md description

`docs/skills.md` is a generated table (`devbot list skills -a`) whose Description column mirrors each skill's SKILL.md frontmatter `description` verbatim — minus the `devbot:` name prefix. No test enforces this sync, so editing a skill description silently desynchronizes the docs row. After changing any SKILL.md `description`, update the matching row in `docs/skills.md` (run `bin/devbot list skills -a | grep <skill>` to get the exact text) and re-run `format-md` — prettier pads the table back to a consistent width. Note the `dev` module ships no tests, so nothing else guards its skills.
