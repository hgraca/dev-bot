---
date: 2026-07-31
keywords: ["devbot", "gather-context", "subagent", "file-production"]
---

## gather-context skill requires subagent delegation to produce report file

When `gather-context` skill is loaded and run inline by DevBot (not as a delegated subagent), the skill's file-production step (write report to `thinking/`, signal `[FINISHED]`) is skipped. DevBot outputs findings conversationally to the human instead of writing a report file. The skill's protocol — produce file → signal `[FINISHED]` with path → orchestrator reads file — only works when run as a subagent that follows agent-communication markers. Fix: delegate to @scout subagent, who runs gather-context properly and produces the report.
