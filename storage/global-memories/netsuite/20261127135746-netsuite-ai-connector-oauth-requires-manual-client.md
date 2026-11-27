---
date: 2026-11-27
keywords: ["netsuite", "mcp", "oauth", "ai-connector"]
aliases: ["4089199", "suitetalk mcp", "Invalid login attempt wrong role or account"]
trigger-on: ["netsuite-mcp-oauth", "netsuite-ai-connector"]
---

## NetSuite's AI Connector MCP cannot be registered dynamically, and a redirect mismatch hides behind a login error

Three traps decide whether an agent connects to `https://<account>.suitetalk.api.netsuite.com/services/mcp/v1/all`. (1) The account host serves authorization-server metadata declaring `issuer: https://system.netsuite.com`, which opencode rejects under RFC 8414 §3.3 — name the document explicitly (`oauth.auth_server_metadata_url`) instead of relying on discovery. (2) The `registration_endpoint` answers `invalid_redirect_uri` to **every** URI tried (loopback with and without a port, `localhost`, `https://example.com`), so dynamic client registration never succeeds: the OAuth 2.0 integration record must be created by hand with Authorization Code Grant and the NetSuite AI Connector Service scope, TBA and Client Credentials unchecked. (3) `redirect_uri` in the config must equal that record's callback character for character; a mismatch is reported by NetSuite as a plain _"Invalid login attempt. Wrong role or account? Choose another role"_ on the login page, which reads like a permissions problem and sends you hunting roles instead of the redirect. The role still needs `MCP Server Connection` (`ADMI_MCP_SERVER`), `Log In using OAuth 2.0 Access Tokens` and `REST Web Services`, and Administrator is rejected by the connector.
