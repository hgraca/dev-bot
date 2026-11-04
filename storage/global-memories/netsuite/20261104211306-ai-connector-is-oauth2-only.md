---
date: 2026-11-04
keywords: ["netsuite", "mcp", "oauth2", "ai-connector-service"]
---

## The NetSuite AI Connector MCP endpoint is OAuth 2.0 only

NetSuite's hosted MCP server (`https://<account>.suitetalk.api.netsuite.com/services/mcp/v1/all`) accepts OAuth 2.0 Authorization Code Grant with PKCE and nothing else. Token-based Authentication and Client Credentials must be cleared on the integration record, and the role needs "Log in using OAuth 2.0 Access Tokens" — not the similarly named TBA permission. A static bearer token works only until the ~60-minute access token expires. The account-specific hostname lowercases the account ID and turns every underscore into a hyphen (`1234567_SB1` → `1234567-sb1`); using the Company Information form verbatim yields a host that never resolves.
