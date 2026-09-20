---
date: 2026-09-17
keywords: ["mcp", "listChanged", "genai-toolbox", "streamable http", "sse"]
trigger-on: ["mcp-list-changed", "genai-toolbox", "mcp-push-channel"]
---

## A bridged or prebuilt MCP server usually has no server→client push channel

`notifications/tools/list_changed` needs two things: the server must declare `capabilities.tools.listChanged: true`, and it must be able to push the notification down an open session. Neither holds for the common dev-bot shape. `genai-toolbox` (a prebuilt distroless binary) hard-codes `listChanged: false` and exposes **no flag** to change it, and it answers `GET` on its MCP endpoint with **405** — so the streamable-HTTP SSE channel a server would push on does not exist either. mcp-proxy is no improvement: it copies the remote's capabilities, so a wrapped `listChanged: false` stays false. Practical consequence: a tool-list change on such a server (a datasource appearing once its DB comes back, a project indexed, a server recovering) is **invisible to a connected client until that client re-lists by reconnecting**. The server side can self-heal freely — the client will not notice. Plan for a client-side refresh (or a reconnect) rather than assuming a notification will arrive, and check `GET` behaviour on the endpoint before designing around server push.
