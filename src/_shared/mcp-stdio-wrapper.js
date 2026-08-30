#!/usr/bin/env node
// =============================================================================
// src/_shared/mcp-stdio-wrapper.js
// MCP stdio wrapper around stdio-transport MCP servers launched via npx/docker.
//
// Several npx-launched MCP servers (playwright, chrome-devtools, codebase-index)
// crash with an unhandled Node EPIPE 'error' event every time the MCP client
// closes the stdio pipe at session teardown — a raw stack trace in the log and
// a non-zero exit (audit-18/19 NOTEs: rotated/*-mcp-*.log crash traces). The
// crash is harmless (it happens at shutdown) but is indistinguishable from a
// live incident in the logs.
//
// This wrapper bridges stdio to the real server and swallows that teardown
// EPIPE, so the process exits cleanly. Everything else passes through.
//
// Usage: node mcp-stdio-wrapper.js <command> [args...]
//   e.g. node mcp-stdio-wrapper.js npx -y @playwright/mcp@0.0.79 --browser chromium
//   (or:  node mcp-stdio-wrapper.js docker run --rm -i mcp/playwright)
//
// Symlinked into projects by each module's init.sh under a module-specific
// name (e.g. .claude/playwright-mcp-wrapper.js, .opencode/chrome-devtools-mcp-wrapper.js).
// =============================================================================

const { spawn } = require("child_process")

const [cmd, ...args] = process.argv.slice(2)
if (!cmd) {
  console.error("Usage: mcp-stdio-wrapper.js <command> [args...]")
  process.exit(2)
}

const child = spawn(cmd, args, { stdio: ["pipe", "pipe", "inherit"] })

// Client stdin -> child stdin (MCP requests)
process.stdin.pipe(child.stdin)
child.stdin.on("error", () => {
  // Client closed stdin before the child was ready — nothing to do.
})

// Child stdout -> client stdout (MCP responses)
child.stdout.on("data", (chunk) => process.stdout.write(chunk))

// The fix: an 'error' listener on our stdout. When the MCP client closes the
// pipe at session teardown, the next write emits EPIPE here; without a
// listener Node treats it as an uncaught error and crashes the process.
process.stdout.on("error", () => {
  // EPIPE at teardown — expected, swallow and let the child finish/exit.
})

child.on("error", (err) => {
  console.error(`mcp-stdio-wrapper: failed to spawn ${cmd}: ${err.message}`)
  process.exit(1)
})

child.on("exit", (code, signal) => {
  if (signal) {
    // Forward the terminating signal so our exit status matches the child's.
    process.kill(process.pid, signal)
  } else {
    process.exit(code ?? 0)
  }
})
