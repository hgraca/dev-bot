---
date: 2026-10-13
keywords: ["devbot", "skills", "frontend", "storybook-deploy", "frontmatter"]
aliases: ["skill name mismatch", "available skills stale", "module skill rename"]
trigger-on: ["devbot-module-skill-name"]
---

## A module skill's loadable name can disagree with its on-disk SKILL.md frontmatter

A devbot module's whole `skills/` directory is symlinked into `.agents/skills/devbot/<module>`, and the harness reports a skill by the frontmatter `name:` — but the harness's registered list is a snapshot, so it can go stale relative to the symlinked files after a skill is renamed (or a rename is reverted). Observed 2026-10-13 in `unified-ui`: `.agents/skills/devbot/frontend` → `dev-bot/src/agentic/frontend/skills` holds `storybook/SKILL.md` with `name: devbot:storybook`, yet `skill("devbot:storybook")` fails and the harness lists `devbot:storybook-deploy` at `frontend/storybook-deploy/` — a path that no longer exists on disk. Rule: when writing a preemptive-skill list or calling `skill`, take the name from the harness's own available-skills list, not from the on-disk frontmatter; treat a disagreement as a stale registry (a reinit should refresh it) rather than editing the skill.
