---
date: 2026-06-14
keywords: ["devbot", "skill", "fixup", "consistency", "review"]
---

## Re-check all downstream sections after a fixup commit to a skill file

When a human stakeholder makes a structural fixup commit to a SKILL.md (e.g. changing project layout from layer-separated to per-module), the upstream sections change but downstream sections may still reference old paths. After a fixup, read the full file end-to-end and cross-reference every path, import, and directory reference in later sections against the new structure at the top. Common drift: Architecture dir trees, code example import paths, roadmaps, and gotchas that reference old directory names.
