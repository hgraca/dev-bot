---
date: 2026-11-02
keywords: ["tools-mcp", "inProcess", "mcp", "heap-snapshot"]
---

# devbot-tools can dispatch a tool in the server process, not a subprocess

## The key

`mcp-meta` may carry `"inProcess": "<handler>"`; `start-tools-mcp.ts` then calls `IN_PROCESS_HANDLERS[<handler>]` instead of `Bun.spawn(["bash", script])`. A `.mcp.sh` body runs as a child with its own heap, so anything that must observe the server itself — a heap snapshot, internal counters — cannot be implemented in the script. The shipped handler is `server-heap-snapshot`, written to `<tmpdir>/devbot-heap-<timestamp>.heapsnapshot` or an explicit `args[0]`.

## Rules that were easy to get wrong

- The key's **presence** marks the tool in-process. Validation must reject empty, non-string, inherited (`toString`) and unknown values at discovery — a truthiness check lets `"inProcess": ""` fall through and spawn the body, the exact outcome the key forbids.
- `timeoutMs` does not apply: the handler runs on the server's event loop and must return.
- The script body should exit non-zero with a diagnostic, so a dispatch regression fails the call loudly instead of silently doing nothing.
- The snapshot is a dump of process memory (environment, tool output, prompt content) — create it exclusively at `0600`; never `chmod` a path after writing it, and never write through a pre-existing path.

## Where it lives

Tool files live in `src/agentic/<module>/tools/`; `_link_tools` (`src/tools/devbot-cli/functions.sh`) farms `*.mcp.sh` into `<devbot_dir>/tools/` on `devbot reinit`. The farm links into the **main checkout**, so a worktree commit is not live until merged and the project is reinit'd — and the running MCP server only picks the tool up after a restart.
