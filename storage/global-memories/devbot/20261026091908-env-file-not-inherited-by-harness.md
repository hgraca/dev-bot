---
date: 2026-10-26
keywords: ["devbot", "env", "harness", "mcp", "tokens"]
aliases: [".env not loaded by harness", "MCP token missing at launch", "env gate abort"]
trigger-on: ["devbot-mcp-env-tokens"]
---

## `devbot up` sources `.env` in a child; MCP `{env:}` tokens must be in the launching shell

`bin/up.sh::_load_env_file` runs `set -a; . .env` inside the `up.sh` process, which `cmd_harness` invokes as a child — its exports never reach the parent or the harness. `src/harnesses/opencode/start.sh` then gates on `_devbot_check_mcp_env_vars` and aborts with "set the missing env vars ... then start devbot from a new terminal". So a token placed only in `dev-bot/.env` satisfies the datasource renderer and docker compose, but NOT an MCP server whose manifest uses `{env:VAR}` (e.g. `SENTRY_ACCESS_TOKEN`, `ATLASSIAN_API_KEY`, `NOTION_MCP_TOKEN`). Fix: export the token in the shell that launches `devbot`, or add `set -a; . /path/to/dev-bot/.env; set +a` to the shell profile. `.env` remains the right home for `${VAR}` datasource/AWS references and compose variables.
