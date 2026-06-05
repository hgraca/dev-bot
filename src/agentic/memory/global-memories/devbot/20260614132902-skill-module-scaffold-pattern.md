---
date: 2026-06-14
keywords: ["devbot", "module", "scaffold", "skill-only", "anatomy"]
---

## Skill-only module scaffold is 4 files + skills directory

A minimal skill-only module consists of exactly: functions.sh (7-line passthrough), install.sh (boilerplate bash/bats check), update.sh (no-op), and skills/<name>/SKILL.md. Always create a tests/ directory (even empty) per gate checklist item 10. No tools/, hooks/, commands/, or init.sh needed for guidance-only modules. The name field in SKILL.md frontmatter must match the parent directory name. install.sh must be idempotent (checks dependencies, never modifies state).
