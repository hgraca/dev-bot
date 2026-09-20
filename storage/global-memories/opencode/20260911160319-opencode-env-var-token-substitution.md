---
date: 2026-09-11
keywords: ["opencode", "env-var", "mcp", "config", "headers"]
trigger-on: ["opencode-env-token", "mcp-header-env-token"]
---

## OpenCode expands `{env:VAR}` at launch; an unset var becomes an empty string

OpenCode substitutes `{env:VAR}` in config string values — including MCP `headers` and `environment` — resolving it at launch from the client's own process env. If the variable is unset, opencode substitutes an **empty string** (no error, no warning). This matters for configs deliberately kept secret-free and portable: `"IJ_MCP_SERVER_PROJECT_PATH": "{env:PWD}"` works because the harness launcher `cd`s to the project root, but a `{env:MY_OVERRIDE}` that was only set when the config was generated (init-time) silently resolves to `""` at launch.

Claude Code's native spelling is different: `.mcp.json`/`.claude` configs use `${VAR}` (expanded in `env`, `command`, `args`, `url`, `headers`), and an unset `${VAR}` is loaded with a warning as **unexpanded literal text** rather than an empty string. dev-bot's translator (`src/_shared/mcp_translate.py`) maps its canonical `{env:VAR}` to each harness's spelling — never write `{env:VAR}` into a claudecode config or `${VAR}` into an opencode one.

Because opencode fails silently, any `{env:VAR}` a generated manifest depends on must be presence-checked at launch (`dev-bot`'s launch gate in `src/_shared/functions.sh`). Verify a token's resolution with `opencode debug config`, which prints the post-substitution value.
