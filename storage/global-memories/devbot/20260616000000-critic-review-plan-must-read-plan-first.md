---
date: 2026-06-16
keywords: ["devbot", "critic", "review-plan", "stall", "context"]
---

## Critic plan review must read plan file before writing review

The critic subagent had a built-in invariant requiring it to write the review file as its first tool call, preventing it from reading the plan file when only a path was provided (not inline content). This caused a `[BLOCKED] context_insufficient` stall. Fix: added explicit "Step 1: Read the plan — MUST" to `review-plan` SKILL.md that instructs the critic to read the plan file at the provided path before writing the review. If the plan is neither embedded inline nor reachable at the path, the critic signals `[BLOCKED] plan_not_accessible`. This eliminates the need for orchestrator to embed full plan content in every critic delegation prompt.
