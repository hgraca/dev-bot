---
date: 2026-05-16
keywords: ["opencode", "tool", "bash", "format", "default"]
---

## Shell wrapper and TS tool wrapper have opposite format defaults by design

When a DevBot opencode tool delegates to a colocated bash script, the two layers intentionally use **different default output formats**:

- **Bash script** (`<tool>.sh`) — defaults to **markdown** (human-readable, for direct CLI use)
- **TS tool** (`<tool>.ts`) — defaults to **json** (structured, for LLM consumption)

The TS tool always passes `--format <fmt>` explicitly to the bash script, so the bash default only matters when the script is invoked directly from a terminal.

**Gotcha**: editing the bash default without also checking the TS tool's `default()` call (or vice versa) breaks one of the two consumers. Always verify both layers when changing format defaults.

Reference: `ripgrep-report` (commits `a15a6fd`, `f457e98`). Cross-ref [[20260515000000-01-wrapping-a-system-cli-tool-as-an-opencode-tool-ts]].
