---
date: 2026-04-17
keywords: ["graphify", "graph"]
---

## M-ARCH-012: Graceful degradation for optional dependencies

Graphify MCP server should work even if graph.json doesn't exist
Design MCP wrappers to exit 0 when dependencies missing rather than failing. Prevents cascading failures in opencode startup.
