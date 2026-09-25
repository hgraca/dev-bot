---
date: 2026-09-25
keywords: ["skill", "description", "frontmatter", "refactor", "operations"]
---

## A skill description may list the skill's bounded operation vocabulary

ADR `20260923120000-skill-descriptions-carry-the-trigger-only` holds that a
`SKILL.md` frontmatter `description` states **when** to use the skill, never
**what** it does. `devbot:refactor` is a deliberate carve-out.

The refactor skill's operations — `rename`, `move`, `extract`, `inline`,
`encapsulate`, `add-parameter`, `remove-parameter`, `remove-unused`, `privatize`,
`promote-readonly` — are themselves trigger keywords. An agent asked to "extract
this method" or "make this readonly" matches the skill by the operation name, so
the description lists them explicitly after the when-to-use clause.

The risk the original rule guards against — a description that grows into
documentation — stays bounded here: the vocabulary is finite and cross-language
(it does not grow with each language), and `tests/ops_table_check.py` fails when
the declared operations and the module's ops table diverge.

The original rule still holds for prose: a description states the trigger and,
for a bounded, user-typed vocabulary, the vocabulary itself — not behaviour,
mechanics or examples.
