---
date: 2026-10-09
keywords: ["devbot", "supervisor", "memory-scoping"]
see: ["ADRs/20261009084426-supervisor-memory-scope-resolution.md"]
---

## Supervisor project memory scoping

Stakeholder decisions (2026-10-09) for a dev-bot **supervisor** project — a session that works across the managed projects registered in `.devbot.global.jsonc::projects`: (D1) supervision is a per-project bool `supervisor` (default `false`) in `.devbot.project.jsonc`, and the supervisor may live anywhere — physical nesting of the managed projects is irrelevant; (D2) the managed set is the global `projects` list minus supervisors; (D3) a session in supervisor S working on child A reads A's vault + the shared global store + S's vault, never an untouched sibling; (D4) scope is resolved from the **files the session touches** (`search-memories --focus <path>`), not an explicit project flag; (D5) writes are routed by the agent per memory to the owning project, cross-project → S, tech-generic → the global store; (D6) a session launched inside a child is unchanged (child + global, never S); (D7) reindex from S builds S + global, and a child's index is refreshed lazily per query; (D8) a non-git supervisor root skips the memory commit with a **notice log line** only, no warning; (D9) the feature is inert unless `supervisor: true`; (D10) working on child A, S honours A's own `commit_memory` and `worktrees`, resolved project-first → global-fallback for A.
