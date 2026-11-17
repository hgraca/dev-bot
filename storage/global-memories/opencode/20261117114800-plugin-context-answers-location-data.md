---
date: 2026-11-17
keywords: ["opencode", "plugin-context", "mcp.list", "response-envelope"]
aliases: ["ctx.mcp.list shape", "plugin api returns location and data"]
trigger-on: ["opencode-plugin-context", "opencode-mcp-list"]
---

## A 2.x plugin context answers `{ location, data }`, not a bare array

Methods on the plugin context mirror the HTTP client, so they return the endpoint's envelope: `await ctx.mcp.list()` yields `{ location: {…}, data: Mcp.Server[] }`, where each server is `{ name, status: { status: "connected" | "disabled" | "pending" | "failed" | "needs_auth" } }`. Code that assumes a bare array (or an older `{ servers }` wrapper) silently sees zero servers and does nothing — the failure looks like "no change", not an error, so it can sit undetected for hours. Read `out.data` first and keep the other shapes as fallbacks. The same envelope applies to other context reads (agents, tools, plugins, sessions), so check the response type before iterating.
