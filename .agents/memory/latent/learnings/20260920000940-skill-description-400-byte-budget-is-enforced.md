---
date: 2026-09-20
keywords: ["skill-description-budget", "skills", "docs-skills"]
---

# Skill descriptions have a test-enforced 400-byte budget

`src/_shared/tests/skill-description-budget_tests.bats` fails any first-party `SKILL.md` whose frontmatter `description` exceeds 400 bytes. The measurement runs from `description:` to the next frontmatter key, quotes included — a rewrite that lands at 451 bytes fails `make test`.

The budget covers the always-on description that every session pays for, so when growing one, cut elsewhere in the same sentence rather than adding a clause. `docs/skills.md` mirrors the description verbatim (see `20260910185716-docs-skills-table-mirrors-skill-descriptions`) and must be updated in the same change, then `format-md`.
