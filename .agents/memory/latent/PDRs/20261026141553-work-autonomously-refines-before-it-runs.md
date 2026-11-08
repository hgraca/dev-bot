---
date: 2026-10-26
keywords: ["devbot", "work-autonomously", "grilling", "interview-me", "refinement"]
aliases: ["autonomous DEFINE", "grill before autonomy"]
see: ["PDRs/20261022193400-work-autonomously-inline-task-and-resume.md"]
---

## `work-autonomously` refines once up front, then runs without asking

The command now carries its own DEFINE as step 2: for a task whose outcome is open it loads `grilling` and `interview-me`, asks the frontier one batched round at a time until it is empty, and stops the turn on the restate (Outcome / User / Why now / Success / Constraint / Out of scope) for an explicit yes. It skips that round when the run is resuming work (an assignment in this session, or a branch already carrying commits or a pull request), when the task is a written spec, or when it is one unambiguous well-scoped change; a public-contract, architecture or migration change confirms the restate even with a spec unless the spec settles it. The round is the run's only planned pause — steps 1 and 3 and the review loop keep their own instructions to ask, and with no human to answer it reports a blocker instead of guessing. This resolves two contradictions that the command previously left to silence: the agent bootstrap made the session-start interview non-negotiable, so the grilling step in `devbot.md` now names command step 2 as that step for these runs; and `interview-me` forbids non-interactive use and its own terminal-turn rule, so the command is the documented exception — the user is live for the opening round, `grilling`'s batched cadence replaces its one-at-a-time one, and the non-interactive rule applies to the autonomous phase that follows.
