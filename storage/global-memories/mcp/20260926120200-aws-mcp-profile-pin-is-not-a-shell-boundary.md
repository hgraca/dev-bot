---
date: 2026-09-26
keywords: ["mcp", "aws", "mcp-proxy-for-aws", "iam", "security"]
trigger-on: ["mcp-proxy-profile-pinning", "aws-mcp-read-only"]
---

## A pinned `mcp-proxy-for-aws` profile bounds the MCP path, not the agent

`--profile <name>` pins which credentials the proxy signs with, and the proxy's only guarantee is that "the agent cannot discover or use other profiles in `~/.aws/config`" — *through the MCP server*. `AWS_MCP_PROXY_PROFILES` **takes precedence** over `--profile` and `AWS_PROFILE`, so merely warning about it leaves a pin advisory: the account check can pass for the pinned profile while the running session is signed with another. AWS's own guidance is explicit that an agent with a shell can call AWS directly — a policy conditioned on `aws:ViaAWSMCPService` blocks the managed-MCP path but not the equivalent CLI command through bash. The boundary is therefore least privilege on the underlying IAM role (it binds both paths), plus a permission boundary or SCP, plus limiting which credentials the machine can reach. A guard/denylist hook is not a boundary.
