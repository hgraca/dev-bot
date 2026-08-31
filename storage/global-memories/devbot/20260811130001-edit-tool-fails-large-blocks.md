---
date: 2026-08-11
keywords: ['devbot', 'edit-tool', 'large-blocks', 'python-replacement']
trigger-on: ['large-file-edit', 'multi-hundred-line-replacement']
---

## Edit tool silently fails on large multi-hundred-line replacements

The `edit` tool (oldString/newString matching) fails to match large code blocks (>~100 lines) due to invisible whitespace differences, even when the content appears identical when read via `Read` tool. When replacing large inline table blocks (200+ lines of JSX), the tool returned "Could not find oldString" repeatedly despite the text matching visually. Solution: use Python scripts with exact `str.find()` matching on unique sentinel markers, then write the file via Python. This approach is reliable for large surgical replacements where the edit tool breaks down.
