---
date: 2026-04-19
keywords: ["opencode"]
---

## M-FLOW-040: Bootstrap file loading redundancy elimination

AGENTS.md contained redundant directive to read bootstrap files when opencode.jsonc already injects them
Keep opencode.jsonc instructions array as the reliable mechanism, remove redundant directives from AGENTS.md - infrastructure-level injection is guaranteed
