---
date: 2026-10-29
keywords: ["auto-dev", "work-autonomously", "command", "rename"]
aliases: ["work-autonomously", "autonomous mode command", "slash command rename"]
see: ["PDRs/20261022193400-work-autonomously-inline-task-and-resume.md", "PDRs/20261026141553-work-autonomously-refines-before-it-runs.md", "PDRs/20261020081822-copilot-review-loop-lives-in-work-autonomously.md"]
---

## The autonomous-mode command is `auto-dev`, renamed from `work-autonomously`

Stakeholder request (2026-10-29): the slash command `work-autonomously` is renamed to `auto-dev`, a shorter name for the same opt-in autonomous mode. Nothing else changes — the inline/file/URL argument handling, the refine-once DEFINE step, workflow selection, skipped check-ins, the pull-request review loop and the stop-one-step-before-merge hand-back all stay as they were. It is a breaking rename of the invokable name: `/auto-dev` is the command and `/work-autonomously` no longer resolves (shipped as `refactor(devbot)!` in GET-E/dev-bot#34).

The older PDRs listed in `see` still name `work-autonomously` because they record decisions taken under that name; the `aliases` here are what make a search for the old name reach this note. The rename needs `devbot reinit` after merge to drop the stale command-farm link — see the command-rename farm-link learning.
