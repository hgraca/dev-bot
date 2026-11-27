---
date: 2026-11-27
keywords: ["opencode", "mcp", "oauth", "jsonc", "config"]
aliases: ["auth_server_metadata_url", "Issuer mismatch RFC 8414", "env and file substitution in opencode.jsonc"]
trigger-on: ["opencode-mcp-oauth", "opencode-config-secrets"]
---

## `oauth.auth_server_metadata_url` bypasses strict issuer checks, and config reads secrets from env or a file

Two opencode configuration facts decide whether an MCP OAuth login is even reachable. First, `opencode.jsonc` substitutes `{env:VAR}` and `{file:path}` into the raw config text before parsing, so a client secret can stay out of the file entirely — `{file:~/…}` expands `~` and trims trailing whitespace, and a missing file or variable substitutes empty rather than failing the load. Second, `oauth.auth_server_metadata_url` takes a metadata document's own `issuer` as the authorization-server URL and skips the RFC 8414 §3.3 check that the document's `issuer` equals the URL it was fetched from — the documented remedy when a server publishes metadata from an account host that declares a different issuer. Note where `{env:VAR}` is resolved: the config is read by the running **server** process, whose environment was captured at launch, so a variable exported after the server started is invisible until opencode restarts; `{file:path}` has no such dependency and is the safer choice for a credential a harness must pick up live.
