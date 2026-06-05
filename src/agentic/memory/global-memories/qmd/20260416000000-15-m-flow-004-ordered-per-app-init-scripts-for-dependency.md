---
date: 2026-04-16
keywords: ["qmd"]
---

## M-FLOW-004: Ordered per-app init scripts for dependency management

DevBot initializes 7 per-project tools (obsidian, opencode, codebase-index, graphify, cass, qmd, session-capture) with interdependencies
Define a fixed init sequence in bin/init.sh and implement each tool's init.sh to be idempotent and order-aware. This ensures dependencies are satisfied and allows tools to assume prior tools have run.
