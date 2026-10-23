---
date: 2026-10-23
keywords: ["workflow", "worktrees", "trunk", "check-ins", "autonomous"]
aliases: ["workflow selection", "trunk workflow", "worktrees workflow", "workflow config key"]
---

## Workflows replace the worktrees flag, with a check-in after every step

Stakeholder decisions of 2026-10-23. `devbot:software-development` defines the end-to-end workflows a task follows and selects one by explicit user instruction, then the project's configuration, then a default; the first two workflows are `worktrees` (default: worktree → atomic commits → review → pull request → hand back without merging) and `trunk` (default branch, no pull request, local review, user gate before pushing). The boolean `worktrees` config key became `workflow: "worktrees" | "trunk"`, and `observability`'s opt-out became `trunk`. In an interactive session every step ends with a short report and a "continue or change something?" question; `/work-autonomously` is the explicit exception — it follows the workflow in use without the check-ins and stops one step before the merge (an open pull request, or reviewed commits with the push still pending), and a no-argument run continues the assignment already in progress rather than asking for a task. The Copilot review loop's mechanics stay in the command rather than in the always-loaded skill.
