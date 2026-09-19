---
date: 2026-09-20
keywords: ["tool-grades", "actor-column", "subagent", "slice-rule"]
see: ["PDRs/20260918122005-01-grade-tools-tool-evaluation-matrix.md", "ADRs/20260918231739-02-stats-reads-tool-grades-csv.md", "ADRs/20260920000940-tool-grades-reporting-model-thresholds-and-quadrants.md"]
---

## Tool grades record the agent that wrote each row, and subagents grade their own slice

Only the primary agent graded, so a session that plans (PO → Architect → Critic) or implements (Tester → Developer → Reviewer) had most of its tool calls graded by nobody. Every subagent now appends its own row before signalling, and a row carries an `actor` resolved `--actor` → `$DEV_BOT_AGENT_NAME` → warn + `unknown`, mirroring the session id. That variable is injected by caching `sessionID → agent` on `chat.params` and reading it back in `shell.env` (see the opencode hooks note); it reaches the bash channel only, never a PTY.

`actor` is **appended** to `BASE_COLUMNS` rather than slotted after `session_id`, because the established four-column prefix is pinned positionally across many fixture assertions — position is cosmetic, since every reader resolves columns by header name. The slice rule becomes "the work since the highest row whose session **and** actor both match mine": without the actor half, an orchestrator's next slice would start after a subagent's row and its own earlier tool use would fall into nobody's slice. Matching is case-insensitive because pre-column rows are backfilled `DevBot` — a one-time migration keyed on the matrix _header_ lacking `actor`, so once the column exists a blank actor means "not known" and is left alone.

The three read-only agents (PO, Architect, Critic) reach the recorder through a narrow `bash` permission grant rather than a lifted deny — see the opencode bash-permission note. Open consequences: the report pools all actors with no breakdown, and it is unverified whether a subagent's bash call carries the child session id, which would make the actor half of the slice rule redundant and inflate the `sessions` denominator.
