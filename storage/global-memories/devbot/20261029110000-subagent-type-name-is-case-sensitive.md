---
date: 2026-10-29
keywords: ["devbot", "subagent", "task-tool", "agent-type"]
trigger-on: ["devbot-delegate-reviewer"]
---

## The task tool's `subagent_type` is case-sensitive: `Reviewer`, not `reviewer`

`task(subagent_type: "reviewer")` fails with `Unknown agent type: reviewer is not a valid agent type`; `task(subagent_type: "Reviewer")` succeeds. The agent protocol says "delegate to `@reviewer`" and the agent-communication skill uses lowercase role names, but the harness registers capitalised types: `Scout`, `PO`, `Architect`, `Critic`, `Developer`, `Reviewer`, `Tester`, `Security`, `Designer`, `Expert`, plus the vendored lowercase ones (`code-reviewer`, `security-auditor`, `test-engineer`, `web-performance-auditor`, `explore`, `general`). Resolve the type from the harness's own agent-type list rather than transliterating the `@name` from the instructions, and treat this exact error as a naming mismatch to retry — not as the subagent being unavailable.
