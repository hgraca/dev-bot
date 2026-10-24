---
date: 2026-10-24
keywords: ["skills", "references", "commit-message", "git-commits"]
---

## A skill that references another skill must not restate it

Stakeholder rule (2026-10-24): when a skill requires another skill to be loaded, it names it, says **when** to load it, and points at it for the rules — it never summarises or restates them. A restatement is worse than silence because it lets the reader finish the first skill believing it has read the rule, so the skill that actually holds it is never loaded, and the two copies drift.

The failure that produced the rule: `devbot:software-development` restated commit craft in prose, so an agent read it, felt done, never loaded `devbot:git-commits`, and wrote 25 commits with paragraph bodies instead of the mandated `Problems:`/`Solutions:` bullet lists.

Enforced in `devbot:create-skill` under "Referencing another skill", with the anti-pattern spelled out (`src/agentic/self-improvement/skills/create-skill/SKILL.md`). Existing skills that still restate a referenced rule (the hub's commit-style bullets, `gh-create-pr`'s copy of the message anatomy) are follow-up work, not a licence to add more.
