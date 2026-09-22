---
date: 2026-09-22
keywords: ["shell", "ripgrep", "rg", "search"]
trigger-on: ["ripgrep", "rg-flags"]
---

## `rg`'s `-r` is `--replace`, not "recursive"

`ripgrep` recurses by default, so there is no recursive `-r` — `-r <text>` is `--replace <text>`, which substitutes the given text for every match **in the output**. Bundling it into a flag cluster (`rg -rn "pattern" src/`) therefore does not mean "recursive with line numbers": it prints the matches with the pattern text replaced by `n`, producing silently mangled output that reads like real file content.

Seen while inspecting a test file: `rg -rn "_wire_mcp" src/harnesses/claudecode/tests/` returned lines like `Tests for claudecode/init.sh's dynamic MCP wiring (n).` — the replacement, not the file. The failure mode is worse than an error, because the result looks like a legitimate search hit and invites misreading the codebase.

Use `rg -n "<pattern>" <dir>` — line numbers are `-n`, recursion is implicit. Reach for `-r` only when a regex replacement is actually wanted, never inside a cluster, and if output looks oddly truncated or generic, check it is not the flag value you passed.
