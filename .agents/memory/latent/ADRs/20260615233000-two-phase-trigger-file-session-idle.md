---
date: 2026-06-15
keywords: ["devbot", "opencode", "remember-session", "plugin"]
see: ["project/20260615233000-execute-after-mid-response-disruption.md", "ADRs/20260615224946-remember-session-git-commit-trigger.md"]
---

## Two-phase trigger-file design for git-commit remember-session capture

The remember-session plugin uses a two-phase design: Phase 1 (`tool.execute.after`) detects git commits and writes a trigger file with commit context. Phase 2 (`event` handler filtering `session.idle`) reads the trigger file and injects the capture prompt. This decouples deterministic commit detection (immediate) from non-disruptive prompt injection (idle-gated). The trigger file (TTL 5 min) bridges the phases. The initial single-phase approach (injecting prompt directly from `tool.execute.after`) was abandoned because the hook fires synchronously mid-response, disrupting the orchestrator's flow and causing stalls. The two-phase design preserves determinism without disruption.
