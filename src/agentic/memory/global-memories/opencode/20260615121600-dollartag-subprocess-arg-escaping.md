---
date: 2026-06-15
keywords: ["opencode", "$", "subprocess", "shell injection", "plugin"]
---

## OpenCode `$` template tag uses argument-array spawning, not shell string concatenation

The `$` tag from `@opencode-ai/plugin` SDK is the canonical subprocess mechanism for OpenCode plugins. It passes interpolated `${variable}` values as separate arguments to `child_process.spawn`, not via shell string concatenation. This makes it immune to shell injection — special characters in interpolated values (quotes, `$`, backticks, `;`) are passed literally as process arguments, never interpreted by a shell. The tag returns a result object with `.quiet()` (suppress output), `.nothrow()` (prevent promise rejection on non-zero exit), and `.exitCode` (read the exit status). Unlike `child_process.execSync`, the `$` tag does not throw on non-zero exits when `.nothrow()` is used. Use `$`tagged \`command\``.nothrow()` instead of `execSync` or `exec` to avoid shell injection and properly handle exit codes.
