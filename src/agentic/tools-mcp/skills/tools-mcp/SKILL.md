---
name: tools-mcp
description: "MCP server (devbot-tools) exposing custom tool scripts from .agents/tools. Each tool self-describes via a mcp-meta subcommand returning JSON metadata. Use this skill whenever working with or extending the devbot-tools MCP server."
---

# Tools MCP

This module provides an MCP server that discovers and exposes executable tool scripts as MCP tools. Tools are discovered from `.agents/tools/`.

## How it works

1. Server boots and scans `.agents/tools/` for `.sh` scripts
2. For each script, it runs `<script> mcp-meta` and parses the JSON output
3. Only tools returning valid `mcp-meta` JSON are exposed — no auto-detection fallback

## Tool metadata via `mcp-meta`

Every tool MUST handle the `mcp-meta` subcommand by printing a JSON object to stdout and exiting 0:

```bash
#!/usr/bin/env bash

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"greet","description":"Greet a user by name with optional enthusiasm","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"CLI args: <name> [enthusiasm]"}},"required":["args"]}}
JSON
    exit 0
    ;;
  *)
    name="${1:-friend}"
    enthusiasm="${2:-normal}"
    case "$enthusiasm" in
      very) echo "HELLO ${name}!!!!!!!!!" ;;
      meh)  echo "oh, hi ${name}." ;;
      *)    echo "Hello, ${name}!" ;;
    esac
    ;;
esac
```

### Metadata format

```jsonc
{
    "name": "greet", // required — MCP tool name (becomes devbot-tools_greet)
    "description": "...", // required — human-readable description
    "parameters": {
        // required — JSON Schema for inputs
        "type": "object",
        "properties": {
            "args": {
                // all tools use a single 'args' string array
                "type": "array",
                "items": { "type": "string" },
                "description": "CLI args: <name> [enthusiasm]",
            },
        },
        "required": ["args"],
    },
}
```

All tools use a single `args` (string array) parameter. The LLM constructs the full CLI command as an array, and the server passes it to the script as positional arguments. This works universally regardless of each script's CLI convention (flags, positional, etc.).

For tools that take no arguments (e.g. fire-and-forget), use an empty `properties: {}` and omit `required`.

## Adding a tool

1. Place a `.sh` script in `.agents/tools/`
2. Make it executable (`chmod +x`)
3. Handle the `mcp-meta` subcommand (see above) — REQUIRED for the tool to be exposed
4. The MCP server picks it up on the next `tools/list` request

## Security

The MCP server executes arbitrary scripts. Only place trusted tools in the tools directories.
