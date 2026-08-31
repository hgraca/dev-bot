---
date: 2026-08-22
keywords: ["graphify", "mcp", "opencode", "devbot"]
trigger-on: ["graphify-mcp-unavailable", "graphify-mcp-launch-race"]
---

## graphify MCP server unavailable when graph.json is absent at session launch

The graphify MCP server (`bash .opencode/graphify-serve.sh graphify-out/graph.json`) exits 0 _silently_ when `graph.json` does not exist — the wrapper is designed to skip ("the MCP server is not needed until the graph is built"). If opencode launches it at session start before the graph is built — common right after `devbot reinit`, where the graph build races the MCP launch — opencode logs `server unavailable key=graphify type=local status=failed` and does **not hot-restart** a failed local MCP server. Result: no `graphify_*` tools for the entire session.

**Resolved (final)**: `graphify/init.sh` writes a dummy empty `graph.json` (`{"directed": true, "multigraph": false, "graph": {}, "nodes": [], "links": []}`) _before_ kicking off the background build. `graphify.serve` accepts it and **hot-reloads** graph.json on every tool call (`_maybe_reload` compares `(mtime_ns, size)`), so it transparently serves the real graph once `graphify update` overwrites the dummy. The earlier "wrapper blocks for graph.json" fix (up to `GRAPHIFY_MCP_WAIT_SECONDS`) was insufficient because opencode marks the server failed at ~37s, before the ~1min build finishes. `graphify.serve`'s `_load_graph` requires a valid node-link graph (empty is fine); non-atomic overwrites during the build are tolerated because `_maybe_reload` catches the transient read error (`except SystemExit: return`) and keeps the previous graph until the next call. The wrapper still resolves `DEVBOT_ROOT` from its symlink target (was unset in the MCP runtime).
