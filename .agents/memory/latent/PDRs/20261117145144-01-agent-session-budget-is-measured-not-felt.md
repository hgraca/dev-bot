---
date: 2026-11-17
keywords: ["session-budget", "context-window", "agents", "handoff"]
see: ["learnings/20261117145144-01-session-usage-limit-unknown-when-model-uncatalogued.md"]
---

## An agent stops on a measured session budget, never on a felt one

Every dev-bot agent carries a `Session budget (MUST)` section requiring a `session-usage` call before it may decide its session is ending or that too little session remains: the transcript's length, an earlier reading and the size of the remaining task list are explicitly not evidence. The cutoff is 90% of the model's context limit — below it the agent keeps working; at or above it the agent stops at the next clean step, states the exact figure, names the step it reached and hands off through `devbot:agent-communication`. A `limit unknown` answer (model missing from the tool's catalogue) is inconclusive and never justifies an early stop. The rationale: a guessed limit is indistinguishable to the human from a measured one, so only the tool's own number may end a session (ARC-1033, PR #114).
