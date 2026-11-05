---
date: 2026-11-05
keywords: ["devbot", "skill", "command", "auto-dev", "review-loop"]
---

# Reusable loop mechanics belong in a skill, not a slash command

## The trap

A slash command (`commands/<name>.md`) is a user-invoked entry point, not something an agent can load with the `skill` tool. A skill that says "the loop lives in `devbot:auto-dev`" therefore sends the agent into a failed `skill("devbot:auto-dev")` lookup, with no hint that the mechanics sit in a markdown file it must read instead.

## The rule

Mechanics an agent must follow belong in `skills/<name>/SKILL.md`, which any agent can load. Keep the command as a thin entry point that names the skill and adds only the user-supplied argument. When a skill must point at a command, name it as the **command** and give its path (`src/agentic/<module>/commands/<name>.md`).

## Why it matters

`devbot:auto-dev` carried ~70 lines of review-loop mechanics (timeline cursor, polling cadence, reply format) that an interactive run could not reuse, and the two skills that referenced it were depending on a command for their own rules. Extracting `devbot:gh-review-loop` removed the duplication and made the mechanics loadable.
