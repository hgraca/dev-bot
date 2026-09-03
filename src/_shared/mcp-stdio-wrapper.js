#!/usr/bin/env node
// =============================================================================
// src/_shared/mcp-stdio-wrapper.js
// MCP stdio wrapper around stdio-transport MCP servers launched via npx/docker.
//
// Two EPIPE failure modes, both from the MCP client closing the stdio pipe:
//
// 1. Session teardown (audit-18/19 NOTEs): the wrapper's own next stdout write
//    throws an unhandled EPIPE. Fixed here with an 'error' listener on our own
//    stdout — the process exits cleanly.
// 2. Teardown mid-handshake (audit-35 FAIL): when the client gives up while a
//    server is still initialising (e.g. a 30s CONNECT_TIMEOUT at session start)
//    and kills this wrapper, the WRAPPED CHILD's stdout pipe is severed too.
//    The child — a separate Node process — then crashes on its next write with
//    an unhandled EPIPE stack trace the wrapper cannot catch. Fixed by
//    preloading mcp-epipe-guard.js into node/npx children via NODE_OPTIONS
//    (--require) so the child's own EPIPE exits cleanly (code 0).
//
// Everything else passes through.
//
// Usage: node mcp-stdio-wrapper.js <command> [args...]
//   e.g. node mcp-stdio-wrapper.js npx -y @playwright/mcp@0.0.79 --browser chromium
//   (or:  node mcp-stdio-wrapper.js docker run --rm -i mcp/playwright)
//
// Symlinked into projects by each module's init.sh under a module-specific
// name (e.g. .claude/playwright-mcp-wrapper.js, .opencode/chrome-devtools-mcp-wrapper.js).
// =============================================================================

const { spawn } = require("child_process")
const fs = require("fs")
const path = require("path")

const [cmd, ...args] = process.argv.slice(2)
if (!cmd) {
  console.error("Usage: mcp-stdio-wrapper.js <command> [args...]")
  process.exit(2)
}

// Real directory of this script. The wrapper is invoked through a symlink from
// a project (.claude/<name>-mcp-wrapper.js), so resolve argv[1] explicitly —
// the guard file lives next to the real wrapper in the dev-bot install.
const sharedDir = path.dirname(fs.realpathSync(process.argv[1]))
const EPIPE_GUARD = path.join(sharedDir, "mcp-epipe-guard.js")

// Child env with the EPIPE guard preloaded (--require) for node/npx children.
// docker children are deliberately excluded: a container does not inherit host
// NODE_OPTIONS and the guard's host path does not exist inside it.
function childEnv(cmd) {
  const base = path.basename(cmd).toLowerCase()
  if (base !== "node" && base !== "nodejs" && base !== "npx" && base !== "npm") {
    return process.env
  }
  if (!fs.existsSync(EPIPE_GUARD)) {
    return process.env
  }
  const requireOpt = `--require=${EPIPE_GUARD}`
  const existing = process.env.NODE_OPTIONS || ""
  if (existing.includes(requireOpt)) {
    return process.env
  }
  return { ...process.env, NODE_OPTIONS: existing ? `${existing} ${requireOpt}` : requireOpt }
}

const child = spawn(cmd, args, { stdio: ["pipe", "pipe", "inherit"], env: childEnv(cmd) })

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
