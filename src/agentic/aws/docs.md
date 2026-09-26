---
title: "AWS"
description: "Work with AWS from an agent through the managed AWS MCP Server, pinned to a named IAM profile."
skills: ["aws"]
mcps:
  aws-mcp: "AWS API access — run_script (Python + boto3), documentation search and curated AWS skills"
---

Work with AWS from an agent: inspect and manage resources, chain API calls in a sandboxed script, search AWS documentation, and load curated AWS skills — through AWS's managed **AWS MCP Server**.

## What it does

Ships one skill (`devbot:aws`), vendors AWS's own `agent-toolkit-for-aws` skills, and wires the AWS MCP Server into the harness. The launcher (`aws-mcp-proxy.sh`) pins the session to a resolved AWS profile and passes the default region as metadata.

The launcher also keeps the agent logged in: `install.sh` runs `aws login` (browser flow, 12 h session auto-renewed every 15 minutes) and `devbot up` re-checks it before the harness starts.

## Read-only is an IAM property

The module imposes **no** read/write restriction on the server — it exposes the full AWS API surface (`run_script` reaches any AWS API). The boundary is the IAM permissions on the resolved profile's role, which is why a profile is required and the ambient default identity is never used implicitly.

Two consequences worth stating plainly:

- Run the agent as a **least-privilege** role — ideally read-only for the services it needs.
- The profile pin scopes the **MCP path only**. An agent with shell access can call AWS directly with whatever credentials the machine holds, so least privilege plus a permission boundary (or SCP) on the role is the control that actually holds.

## Configuration

| Key | Environment | Resolution |
| --- | ----------- | ---------- |
| `aws_profile` (**required**) | `AWS_PROFILE` | project `.devbot.project.jsonc` → global `.devbot.global.jsonc` |
| `aws_region` | `AWS_REGION` | project → global → `aws configure get region` → `us-east-1` |

Set the profile in the environment or a config file; with neither, the MCP server refuses to start rather than fall back to the default identity.

`AWS_MCP_PROXY_PROFILES` overrides `aws_profile` inside the proxy (it lets an agent switch profiles per call) — the launcher warns when it is set, since it silently unpins the session.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [Datasources](/modules/agentic/datasources) — database and Redis data access
