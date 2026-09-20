---
date: 2026-09-08
keywords: ["mcp", "claudecode", "mcp.json", "env", "opencode"]
---

## Claude Code .mcp.json and opencode config expand env vars natively — never resolve secrets at registration

Both MCP clients interpolate environment references in their server config at **launch time**, each with its own syntax: Claude Code expands `${VAR}` (and `${VAR:-default}`) in `command`, `args`, `env`, `url` and `headers` of `.mcp.json`; opencode expands `{env:VAR}` in its `mcp` entries' `environment`/`headers`/`oauth` values. The premise "Claude Code's `.mcp.json` env is literal" is false — an adapter that resolves secrets into the config file at registration writes them in plaintext, couples the result to the registration shell's environment, and re-implements parsing the client already does. Write the native token (`${VAR}` / `{env:VAR}`) into the config and let the client resolve it. An unset variable with no `${VAR:-default}` makes the client load the config with a warning and register the unexpanded text — so whole-value indirection is the safe pattern; embedding a token inside a URL/path diverges silently between clients that spell the syntax differently.
