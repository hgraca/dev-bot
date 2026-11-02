---
name: devbot:tools-mcp
description: "Use when working with or extending the devbot-tools MCP server. Triggers on 'mcp server', 'mcp-meta', 'custom tool'."
---

# Tools MCP

This module provides an MCP server that discovers and exposes executable tool scripts as MCP tools. Tools are discovered from `.agents/tools/`.

## How it works

1. Server boots and scans `.agents/tools/` for `*.mcp.sh` scripts (only files with the `.mcp.sh` extension are MCP tools — plain `.sh` helpers, `.ts` hook targets, and `.py` implementations are ignored)
2. For each script, it runs `<script> mcp-meta` and parses the JSON output
3. Only tools returning valid `mcp-meta` JSON are exposed — no auto-detection fallback

## Tool metadata via `mcp-meta`

Every tool MUST be a `*.mcp.sh` script that handles the `mcp-meta` subcommand by printing a JSON object to stdout and exiting 0:

```bash
#!/usr/bin/env bash
# Save as: .agents/tools/greet.mcp.sh

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
  "timeoutMs": 900000, // optional — overrides the 120s default bound
  "inProcess": "server-heap-snapshot", // optional — run in the server, not a subprocess
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

**`timeoutMs`** is optional. The server kills a tool's whole process group at the default bound
(`TOOLS_MCP_TIMEOUT_MS`, 120 000 ms). A tool that legitimately outlives it — an image pull, a
container build, a canary per source — declares its own bound here, which replaces both the default
and the environment value, so an operator cannot cap a tool that declares more. Anything that is not
a positive integer of at most 2 147 483 647 ms is ignored: a malformed value falls back to the
default rather than removing the bound (a larger delay is clamped to 1 ms by the runtime, which
would kill the tool instantly).

### In-process tools

A tool that needs the server's own heap — or any state a child process cannot reach — declares
`"inProcess": "<handler>"` in its `mcp-meta`, and the server calls that handler instead of spawning
the script. The script body never runs, so it should exit non-zero with a diagnostic if executed
anyway: that turns a dispatch regression into a loud failure rather than a silent one.

The handler is registered in `start-tools-mcp.ts` (`IN_PROCESS_HANDLERS`), keyed by that value. It
receives the same `args` array and returns the text result. The key's presence marks the tool
in-process — which is why a value that is empty, not a string, or not a registered handler is
skipped with a log rather than falling back to spawning the script. `timeoutMs` does not apply: the
call runs in the server's event loop, so the handler must return.

The shipped in-process tool is `heap-snapshot` (`tools/heap-snapshot.mcp.sh`), which writes a V8
heap snapshot of the server process to `args[0]`, defaulting to
`<tmpdir>/devbot-heap-<timestamp>.heapsnapshot`. The file is created exclusively (`O_EXCL`) with
`0600` permissions: an existing file or a symlink at that path fails the call instead of being
written through.

## Output contract

- **stdout** is the tool's result — what the agent reads.
- **stderr** carries diagnostics (`WARN:` / `ERROR:` / `FATAL:`). A non-zero exit
  fails the call, and stderr is returned as the failure message.
- A tool that exits **0 with empty stdout** has its stderr returned instead of a
  generic success line, so a tool that fails open can still say why. A non-empty
  stdout is returned as-is: keep a `--json` payload on stdout and put every
  diagnostic on stderr.

## Adding a tool

1. Place a `*.mcp.sh` script in `.agents/tools/` (the `.mcp.sh` extension is what marks it as an MCP tool)
2. Make it executable (`chmod +x`)
3. Handle the `mcp-meta` subcommand (see above) — REQUIRED for the tool to be exposed
4. If `mcp-meta` declares `inProcess`, register the handler in `start-tools-mcp.ts`
5. The MCP server picks it up on the next `tools/list` request

## Security

The MCP server executes arbitrary scripts. Only place trusted tools in the tools directories.

An in-process tool shares the server's memory. `heap-snapshot` writes a dump of the whole process
(environment, tool output, prompt content) to an owner-only file created exclusively (`0600`, never
written through a pre-existing path) — treat that file as sensitive.
