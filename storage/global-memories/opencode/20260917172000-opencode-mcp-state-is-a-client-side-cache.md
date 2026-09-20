---
date: 2026-09-17
keywords: ["opencode", "mcp status", "query cache", "connect disconnect"]
trigger-on: ["opencode-mcp-status", "mcp-reconnect", "mcp-badge-stale"]
---

## opencode's MCP state is a client-side cache — an API reconnect cannot clear it

The TUI renders MCP state from a cached query (`queryKey: [*, directory, "mcp"]`, fed by `client.mcp.status()` on the v1 protocol path), and only a **client action** writes that store: the MCP dialog's toggle refreshes it explicitly (`f.set("mcp", await client.mcp.status())`), while merely opening the dialog does not refetch. So a server genuinely restored by any external means — an API-driven `mcp.connect`, a plugin — can be fully live, its tools callable by the model, while the red badge persists indefinitely. The remedy for a stale badge is the dialog toggle (keybind `mcp_list`, unbound by default; `dialog.mcp.toggle` is `space`) or a client restart. Verified live: a tool call succeeded through a reconnected server while the badge still read `failed`.

Related, and the more expensive half of the lesson: `connect()` alone does **not** rebuild an MCP client opencode has already registered, tool definitions included. A bare connect re-handshakes the transport and reads back as `connected`, yet the tool stays uncallable; `disconnect` then `connect` is the pair that restores it, which is exactly what opencode's own toggle performs (`if status === "connected" → disconnect, else → connect`). Any automation that wants to restore a broken MCP server must therefore tear the session down first — and should not expect it to fix the badge.
