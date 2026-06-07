---
date: 2026-07-31
keywords: ["devbot", "gather-context", "scout", "subagent"]
see: ["project/20260731173000-gather-context-requires-subagent-delegation.md", "ADRs/20260731173000-remove-agentic-tools-cli.md"]
---

## Delegate `gather-context` to @scout subagent instead of running inline

Changed DevBot's Session Start to delegate context gathering to @scout (subagent) rather than running `gather-context` skill inline. The `gather-context` skill's protocol (produce report file → signal `[FINISHED]` with path → orchestrator reads file) is designed for subagent delegation. Running it inline conversationally causes the file-production step to be skipped because DevBot outputs findings directly to the human. @scout runs as proper subagent, follows the full protocol, and produces the report file on disk.
