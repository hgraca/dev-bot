---
date: 2026-08-23
keywords: ["devbot", "cli", "failure-output", "logging", "functions.sh"]
---

## CLI failure-output prefix convention

All CLI scripts must emit failure information with tiered, machine-greppable prefixes: `WARN:` for a hint something might be wrong, `ERROR:` for a recoverable error, `FATAL:` when no recovery is possible and the script exits. The shared `functions.sh` helpers implement this — `_notice` → `NOTICE:` (stdout), `_warn` → `WARN:` (stdout), `_error` → `ERROR:` (stderr), and a new `_fatal` → `FATAL:` (stderr). Error/fatal messages go to stderr so they surface instead of being swallowed by `$(…)` command substitution. Standalone scripts that do not source `functions.sh` (e.g. `graphify.sh`, the `.mcp.sh` tools) emit the same prefixes via raw `echo "FATAL: …" >&2`. The convention is documented in the `devbot.md` and `developer.md` agent profiles. Only `_error …; exit 1` sites were converted to `_fatal`; recoverable sites (`return 1`, collect-all-then-fail) remain `_error`.
