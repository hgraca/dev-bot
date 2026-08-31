---
date: 2026-05-17
keywords: ["opencode", "plugin", "test", "drift-guard"]
---

## Test drift-guard anchors must match exact SKILL.md wording

When a test uses a string anchor to locate a section in a SKILL.md file (e.g. `lines.findIndex(l => l.startsWith("Every agent must end..."))`) and the SKILL is later reworded, the anchor silently stops matching and the test throws a parse error rather than a meaningful assertion failure. The fix is to update the anchor string in the test to match the current SKILL wording exactly. Pattern: search for the anchor string in the SKILL file before assuming the test is broken for another reason — a wording mismatch is the most common cause of `"anchor sentence not found"` errors in drift-guard tests.
