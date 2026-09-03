#!/usr/bin/env node
// =============================================================================
// src/_shared/mcp-epipe-guard.js
// EPIPE-swallowing shim preloaded into npx/node-launched MCP server children.
//
// mcp-stdio-wrapper.js guards its OWN stdout against the teardown EPIPE, but a
// wrapped child is a separate process: when the MCP client tears the wrapper
// down mid-handshake (e.g. a 30s CONNECT_TIMEOUT at session start — audit-35
// FAIL), the child's stdout pipe is severed and the child's own next write
// throws an unhandled EPIPE — a raw stack trace in the log that is
// indistinguishable from a live incident, and one the wrapper structurally
// cannot catch.
//
// This shim is injected into the child via NODE_OPTIONS=--require=<this file>
// (set by mcp-stdio-wrapper.js for node/npx children only). It installs an
// 'error' listener on the child's own stdout/stderr so an EPIPE at teardown
// exits cleanly (code 0) instead of crash-logging.
//
// Usage: (never invoked directly — loaded via NODE_OPTIONS by the wrapper)
// =============================================================================

function guard(stream, name) {
  stream.on("error", (err) => {
    if (err && err.code === "EPIPE") {
      // The reader (MCP client / wrapper) is gone — the session is over.
      // Exit cleanly so the log shows no crash trace.
      process.exit(0)
    }
    // A non-EPIPE stdout/stderr error is a real transport failure: report it
    // concisely (no raw stack) and exit non-zero so it stays visible.
    try {
      process.stderr.write(
        `[mcp-epipe-guard] ${name} error: ${err && err.code ? err.code : String(err)}\n`
      )
    } catch (_) {
      // stderr itself is gone — nothing left to report to.
    }
    process.exit(1)
  })
}

guard(process.stdout, "stdout")
guard(process.stderr, "stderr")
