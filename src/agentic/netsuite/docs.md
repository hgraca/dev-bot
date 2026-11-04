---
title: "NetSuite"
description: "Oracle NetSuite ERP from an agent, through the official NetSuite AI Connector Service MCP server."
mcps:
  netsuite-account_id: "NetSuite records, saved searches, reports and SuiteQL"
---

Work with NetSuite from an agent: query records, run saved searches and reports, and execute SuiteQL, through Oracle's own **NetSuite AI Connector Service** MCP server.

## What it does

Registers one MCP server per configured NetSuite account, named `netsuite-<account_id>` and pointing at that account's AI Connector endpoint:

```text
https://<account_id>.suitetalk.api.netsuite.com/services/mcp/v1/all
```

The name includes the account because opencode stores MCP authentication per server name: naming it `netsuite-<account_id>` lets a production account and a sandbox stay authenticated side by side.

The server is declared `enabled: false` by default — wired but not started. Connect it from the harness when you need it, and no process or tool schema is paid for otherwise. The module also vendors Oracle's official `netsuite-suitecloud-sdk` agent skills as an external module, so the agent knows NetSuite's tool-selection order, SuiteQL safety rules, and multi-subsidiary/currency conventions.

## Configuration

Set the NetSuite account ID once. A project value overrides the global one.

```jsonc
// .devbot.global.jsonc — or .devbot.project.jsonc to override per project
{ "netsuite": { "account_id": "1234567" } }
```

`account_id` is the value NetSuite shows under **Setup → Company → Company Information** — for example `1234567`, or a sandbox ID such as `1234567_SB1`. The emitted hostname lowercases it and turns underscores into hyphens (`1234567-sb1`), which is the form NetSuite's own domain uses.

Run `devbot reinit` (or just start devbot) after changing it; the module emits the harness manifests from it.

The server is off by default. To wire it on from configuration instead of the harness dialog, set `enabled`:

```jsonc
{ "netsuite": { "account_id": "1234567", "enabled": true } }
```

## Enabling and authenticating

- **opencode** — open the MCP dialog (`/mcp`), connect `netsuite-<account_id>`, and authorise in the browser. opencode stores and refreshes the tokens; `opencode mcp auth netsuite-<account_id>` runs the same flow from a shell, and `opencode mcp logout netsuite-<account_id>` clears it.
- **claudecode** — a disabled server is omitted from `.mcp.json`. Set `enabled: true` in the config above and run `devbot reinit`; the emitted `.claude/netsuite-<account_id>.mcp.json` is regenerated on every init, so editing it by hand does not survive. Then authorise with `/mcp` inside a session.

The AI Connector Service accepts **OAuth 2.0 only** — Oracle requires the Authorization Code Grant with PKCE and rejects Token-based Authentication and Client Credentials for this scope. Set up the NetSuite side first:

1. Enable **Server SuiteScript**, **OAuth 2.0**, and **REST Web Services**.
2. Install the **MCP Standard Tools** SuiteApp from the SuiteApp Marketplace.
3. Give the connecting user a **non-Administrator** role with **MCP Server Connection**, **Log in using OAuth 2.0 Access Tokens**, and (for record tools) **REST Web Services**. Administrator is rejected by the connector.
4. Create an OAuth 2.0 integration record with **Authorization Code Grant**, the **NetSuite AI Connector Service** scope, and every Token-based Authentication and Client Credentials box cleared. Oracle creates one automatically for Claude clients; for another client, create it yourself and keep the client ID/secret.

Because authorisation is a normal NetSuite sign-in, the connection can run as a **different user and role** from your own browser session: open the auth flow in a private window, sign in as the dedicated integration user, and pick the scoped role on the consent page. The token then acts as that user under that role, whatever you are logged into in your own browser.

Access tokens last about an hour and are refreshed automatically while the refresh token lives; revoking the connection in NetSuite ends it regardless.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [MCPs](/mcps) — the full server inventory
