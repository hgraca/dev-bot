---
date: 2026-08-10
keywords: ["shell", "sed", "quoting"]
trigger-on: ["sed-inline-replacement", "sed-code-editing", "shell-quoting"]
---

## sed inline replacement with single quotes inside code mangles string literals

When using `sed -e "s/pattern/replacement/"` or `sed -e 's/pattern/replacement/'` on PHP/JS source files, single quotes inside the replacement string interact with the shell quoting and can produce broken code (e.g., `?? '>'` becoming `''>='`). The issue occurs because sed does not treat the replacement as a literal string when quotes are improperly nested. Fix: use double-quote wrapping for the sed expression and escape any double quotes inside the replacement, or use `sed` with a script file (`-f`). For simple literal replacements in code files, `git add -p` with edit mode or direct `Edit` tool calls are safer alternatives.
