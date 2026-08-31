---
date: 2026-08-13
keywords: ["opencode", "format-md", "file.edited", "prettier", "markdown"]
trigger-on: ["markdown-edit", "format-md-hook"]
---

## format-md hook reformats the whole .md file on edit, producing wide diffs

The `on-file_edited-format-md` plugin hook runs prettier over the *entire* `.md` file whenever it is saved (via the `edit` tool, `write` tool, or any external write). A surgical edit therefore yields a much wider diff than the change itself: prettier re-aligns every table column and normalizes `*italic*` emphasis to `_italic_` across the whole file, mixing formatting churn into the commit. This is expected, not a defect — don't spend time investigating why a 2-line markdown edit shows a 40-line diff. Distinct from the `edit`-tool JSON auto-format: that is the tool itself and only affects JSON/JSONC, whereas this is a plugin hook that fires for all markdown. Observed when folding `git-rules` into `src/agentic/git/skills/` (a 2-line table edit became a 42-line diff).
