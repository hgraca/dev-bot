---
date: 2026-11-27
keywords: ["opencode", "mcp", "oauth", "cimd", "dcr"]
aliases: ["redirect_uri is not registered for client", "unauthorized_client", "client.json portless loopback"]
trigger-on: ["opencode-mcp-oauth", "mcp-remote-oauth-login"]
---

## opencode picks CIMD first, and a portless client document fails every server with a fixed callback

A remote MCP server's OAuth login can die with `unauthorized_client / redirect_uri is not registered for client: http://127.0.0.1:<port>/callback` even though the server works in other clients. opencode advertises itself through CIMD — `client_id=https://opencode.ai/oauth/opencode/client.json` — and that document registers only **portless** loopback redirects (`http://127.0.0.1/callback`, `http://localhost/callback`, `http://127.0.0.1/mcp/oauth/callback`). opencode binds an ephemeral port unless told otherwise, so a strict authorization server (Atlassian is one) rejects the pair outright. The registration mode chosen is logged as `mcp oauth client registration selected … registration=cimd|dcr|static`, and in the source (`packages/core/src/mcp/oauth.ts`) CIMD is only selected when **neither** `oauth.client_id` **nor** `oauth.redirect_uri` is configured — so setting either one switches the flow to DCR or a static client and works around the bug. With DCR, set `oauth.redirect_uri` to a fixed loopback port so the dynamically registered callback matches the listener (`callback_port` / the redirect's port decide the bind); with a hand-registered client, set `oauth.client_id` (+ `client_secret`) and the exact redirect it pinned. Version 2.4.2 still chooses CIMD, so this is not fixed by upgrading.
