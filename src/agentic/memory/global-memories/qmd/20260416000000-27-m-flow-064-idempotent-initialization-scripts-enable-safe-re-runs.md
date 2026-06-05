---
date: 2026-04-16
keywords: ["qmd"]
---

## M-FLOW-064: Idempotent initialization scripts enable safe re-runs

Installation scripts are called multiple times (during setup, upgrades, re-initialization). Using state.mark() / state.done() and idempotent operations (qmd collection add, opencode.upsert_mcp) prevents errors and duplicate work.
Design initialization scripts to be idempotent. Use state tracking for one-time operations (binary installs, git hooks). Use idempotent functions for configuration updates (collection add, MCP upsert). This allows users to safely re-run initialization without side effects.
