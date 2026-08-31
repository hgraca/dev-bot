---
date: 2026-06-15
keywords: ["shell", "subshell", "stdout", "stderr", "command-substitution"]
---

## Status output helpers corrupt arithmetic when function runs inside $()

When a bash function that prints status messages (using helpers that write to stdout, not stderr) is called inside `$()` for return-value capture, all stdout gets captured — including ANSI escape codes from colored output. If the captured text is used in an arithmetic expression like `$((x + $(func)))`, the non-numeric content causes a syntax error. With `set -e`, the script exits immediately with no visible error. Fix: redirect all status output inside such functions to stderr via `>&2`, keeping only the return value on stdout. Applies to any function called via command substitution that mixes status/logging with a return value.
