---
date: 2026-06-15
keywords: ["opencode", "format-json", "plugin"]
---

# format-json tool stdin timeout caused silent failures on large directories

The format-json plugin's stdin read had a 500ms timeout, causing silent failures when piped large file lists from stdin (e.g., recursive directory walks). The tool also lacked an explicit error for missing path argument, returning silently. Fixed by: (1) increasing stdin timeout to 5000ms, (2) adding explicit error exit when no path argument is provided, (3) adding directory exclusions for `no-vcs`, `.git`, `node_modules`, `storage`, `tests`, `vendor`, `__pycache__` to prevent the tool from walking into large generated or vendored directories.
