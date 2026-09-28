---
name: devbot:aws
description: "Use when working with AWS through a configured connection — reading or managing AWS resources, sandboxed scripts, IaC (CDK/CloudFormation), serverless, containers, or when AWS credentials or region are needed. Triggers on 'aws', a service name like EC2, S3, Lambda, EKS, RDS or ElastiCache, an ARN, or an account id."
---

# AWS

This module wires the Agent Toolkit for AWS into dev-bot. It provides three things:

1. **AWS MCP servers** (`aws-<connection>`) — the full AWS API surface reached through sandboxed script execution, plus real-time docs search. One server per configured **connection**.
2. **AWS skills** — curated packages installed from `aws/agent-toolkit-for-aws` (see `.agents/skills/agent-toolkit-for-aws/`).
3. **AWS agent rules** — guidance in `.agents/memory/active/aws-agent-rules.md`.

## Connections

An AWS **connection** is a named identity plus a region. Connections are declared once in `.devbot.global.jsonc`, and each project opts in by name.

```jsonc
// .devbot.global.jsonc
"aws_connections": {
  "aws-prod-ro": {
    "region": "eu-central-1",
    "account_id": "123456789012", // optional — asserted at launch
    "env": {
      "AWS_ACCESS_KEY_ID": "${AWS_PROD_RO_KEY_ID}",
      "AWS_SECRET_ACCESS_KEY": "${AWS_PROD_RO_SECRET}"
    }
  },
  "aws-dev": { "region": "eu-central-1", "profile": "aws-dev" }
}
```

```jsonc
// .devbot.project.jsonc — opt in by name
"aws_connections": ["aws-prod-ro"]
```

`devbot init`/`reinit` wires one MCP server per selected connection, named `aws-<connection>`. A connection that is declared but not selected is not wired; a selected one that is not declared warns.

## Credentials

Non-interactive by design — no `aws login`, no `aws sso login`, no browser. A connection carries **exactly one** of:

- **`env`** — credential values, literal or `${VAR}`. The launcher loads the repo `.env` and the shell environment, resolves the references, and hands the values to the proxy through its **environment** (never the command line, which is visible in `ps`). A missing referenced variable stops the server. This form fixes the identity to that exact key pair.
- **`profile`** — a profile in the shared AWS config (`~/.aws/config`, with the keys in `~/.aws/credentials`); nothing credential-shaped enters dev-bot config. Best used as an assume-role over a source key limited to `sts:AssumeRole`.

Declaring both is rejected: credential precedence between an explicit profile and explicit environment keys would be ambiguous.

**`account_id`** (optional) asserts the identity. The launcher calls `sts get-caller-identity` and refuses to start when the reported account differs, so a stale, wrong or swapped key fails loudly instead of silently running as another account.

## Read-only is an IAM property

The module imposes no read/write restriction — the server exposes the full AWS API surface. The boundary is the IAM policy on the connection's identity, and the connection pin covers the **MCP path only**: an agent with shell access can still reach AWS directly with whatever credentials the machine holds. Least privilege on the identity, plus a permission boundary or SCP, is the control that holds. `AWS_MCP_PROXY_PROFILES` would let an agent switch profiles inside the proxy — the launcher warns when it is set.

## Region

A connection's `region` sets the default region for its operations. When it is absent the launcher falls back to `AWS_REGION`, then `aws configure get region`, then `us-east-1`.

## When to Use What

| Need                                                                        | Use                                                      |
| --------------------------------------------------------------------------- | -------------------------------------------------------- |
| Inspect or manage AWS resources, run sandboxed scripts, search AWS docs     | **AWS MCP server** (`aws-<connection>` tools)            |
| Service-specific guidance (CDK, serverless, containers, billing, SDK usage) | **AWS skills** (`.agents/skills/agent-toolkit-for-aws/`) |
| One-off CLI commands and identity checks                                    | **AWS CLI** (`aws ...`)                                  |
| Before acting, confirm the rule about the MCP server / discovering skills   | **aws-agent-rules.md**                                   |

## Troubleshooting

| Symptom                                                        | Fix                                                                                                         |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| `Unable to locate credentials`                                 | Check the connection's `env` references resolve (repo `.env` or shell), or that the profile exists          |
| `ExpiredToken`                                                 | The static credential or role session expired — refresh the source; nothing re-authenticates on your behalf |
| Server refuses to start; identity is not the expected account  | The connection's `account_id` pin rejected it — fix the key or the pin                                      |
| MCP server won't start (`mcp-proxy-for-aws-cli` not installed) | `devbot install` (installs the proxy); ensure `~/.local/bin` is on PATH                                     |
| A connection is missing in this project                        | Declare it in `.devbot.global.jsonc` and opt in via `aws_connections`                                       |
| Skills missing                                                 | `devbot module install` (clones the toolkit repo), then re-init the project                                 |
