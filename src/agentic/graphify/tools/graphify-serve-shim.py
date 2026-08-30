#!/usr/bin/env python3
"""Shim around `python -m graphify.serve` for MCP stdio servers.

Runs graphify.serve exactly like `python -m graphify.serve <graph.json>` does,
but swallows the BrokenPipeError that the mcp SDK's stdio_server stdout_writer
raises when the MCP client closes the stdio pipe at session teardown. Without
this, every session end logs a full traceback and exits non-zero (audit-18
NOTE: `rotated/*graphify-mcp-*.log` crash traces).

The wrapper (start-graphify-mcp.sh) execs this shim instead of `-m graphify.serve`,
so the fix lives in-repo (the graphify.serve module itself is the upstream
`graphifyy` pip package — not patchable from here).

Usage: python3 graphify-serve-shim.py <graph.json>
"""

import runpy
import sys


def _is_broken_pipe(exc: BaseException) -> bool:
    if isinstance(exc, BrokenPipeError):
        return True
    # Python 3.11+ wraps asyncio task failures in an ExceptionGroup; the mcp
    # SDK raises inside one when the client closes the pipe at teardown.
    return any(_is_broken_pipe(e) for e in getattr(exc, "exceptions", ()) or ())


if __name__ == "__main__":
    try:
        # runpy.run_module(..., run_name="__main__") replicates `python -m`
        # semantics; argv[1:] (the graph.json path) passes through untouched.
        runpy.run_module("graphify.serve", run_name="__main__")
    except BaseException as exc:
        if _is_broken_pipe(exc):
            # MCP client closed the stdio pipe at session teardown — expected.
            sys.exit(0)
        raise
