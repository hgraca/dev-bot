---
date: 2026-09-16
keywords: ["shell", "pgrep", "pkill", "self-match"]
trigger-on: ["shell-pgrep-self-match", "shell-pkill-pattern"]
---

## `pgrep -f <pattern>` matches the shell you are running it from — and kills it

`pgrep -f` matches against the **full command line**, and the command line of the shell executing your command contains the pattern itself. A loop like `for p in $(pgrep -f "bats-core"); do kill "$p"; done` therefore includes its own shell, kills it, and the caller sees the command hang or die mid-way (the tool reported a timeout, not an error). Use the bracket trick so the pattern does not match its own literal text: `pgrep -f "[b]ats-core"`, or exclude `$$`/`$PPID` explicitly. Applies equally to `pkill -f`. Worth remembering whenever one process is asked to clean up processes selected by a pattern — the selection can include the selector.
