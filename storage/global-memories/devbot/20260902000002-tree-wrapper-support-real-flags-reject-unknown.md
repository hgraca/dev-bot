---
date: 2026-09-02
keywords: ["devbot", "tree", "mcp", "flags", "cli"]
trigger-on: ["tree-max-depth", "mcp-unknown-flag"]
---

## Wrapping a CLI tool as MCP: support the tool's real flags, reject invented ones with a usage error

Two audits hit opposite ends of the same trap in the `tree` MCP wrapper. First
(audit-26): the wrapper silently treated an unsupported flag (`--depth 1`) as
a path and printed "skipped non-existent paths" — fix was to reject unknown
`--*` flags with a usage error. Then (audit-28): the wrapper rejected ALL
flags, including `--max-depth` / `-L` which real `tree` genuinely supports
(`-L level`) — fix was to accept `--max-depth N`, `--max-depth=N`, and `-L N`
(validated as positive integers, `^[1-9][0-9]*$` — NOT `[0-9]+`, since
`tree -L 0` errors with "Invalid level, must be greater than 0") and pass
through as `tree -L N`. Lessons: (1) know the wrapped binary's real flag set
before deciding what to reject; (2) validate ranges yourself and emit your own
usage error rather than leaking the binary's message; (3) test the equals-form
(`--max-depth=N`) separately from the space-separated form — they are distinct
parse branches.
