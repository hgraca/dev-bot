---
date: 2026-04-19
keywords: ["promptfoo", "eval"]
---

## M-ARCH-032: Evaluation framework integration architecture

Adding promptfoo as agent evaluation framework to existing system
Evaluation tools should follow CLI tool patterns (npx-based) rather than MCP server patterns. Use ephemeral servers and fixture isolation to prevent side effects on the main codebase.
