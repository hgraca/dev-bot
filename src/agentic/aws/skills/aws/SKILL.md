---
name: aws
description: "Work with AWS — authenticate, resolve region, and use AWS services via the AWS MCP server (aws-mcp), the installed AWS skills, and the AWS CLI. Use this skill for any AWS task: reading/writing resources, IaC (CDK/CloudFormation), serverless, containers, or when AWS credentials or region configuration is needed — even if the user only names a service like S3, Lambda, or EC2."
---

# AWS

This module wires the Agent Toolkit for AWS into dev-bot. It provides three things:

1. **AWS MCP server** (`aws-mcp`) — full AWS API access, sandboxed script execution, and real-time docs search through a single authenticated endpoint.
2. **AWS skills** — curated packages installed from `aws/agent-toolkit-for-aws` (see `.opencode/skills/agent-toolkit-for-aws/`).
3. **AWS agent rules** — guidance in `.agents/memory/active/aws-agent-rules.md`.

## Authentication

Credentials come from `aws login` (browser flow), which writes a short-lived session to `~/.aws/`. The MCP server runs with `--skip-auth`, so it rides on that ambient session.

- Check you are authenticated: `aws sts get-caller-identity`
- Authenticate: `aws login`
- Credentials are valid **12 hours**, renewable for **90 days** without re-authenticating in the browser.

`devbot` (and `devbot up`) automatically ensures you are logged in — if not, it triggers `aws login` before the harness starts.

## Region

The MCP proxy resolves the region with this precedence (first non-empty wins):

1. `AWS_REGION` environment variable
2. `aws_region` in `.devbot.project.jsonc` (per-project override)
3. `aws_region` in `.devbot.global.jsonc` (global default)
4. `aws configure get region` (ambient `~/.aws/config`)
5. `us-east-1`

To change the region for a single project, add `"aws_region": "<region>"` to that project's `.devbot.project.jsonc`.

## When to Use What

| Need                                                                            | Use                                                        |
| ------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Inspect or mutate AWS resources, run sandboxed scripts, search AWS docs         | **AWS MCP server** (`aws-mcp` tools)                       |
| Service-specific guidance (CDK, serverless, containers, billing, SDK usage)     | **AWS skills** (`.opencode/skills/agent-toolkit-for-aws/`) |
| One-off CLI commands, auth checks, `aws configure`                              | **AWS CLI** (`aws ...`)                                    |
| Before acting, confirm the rule about using the MCP server / discovering skills | **aws-agent-rules.md**                                     |

## Troubleshooting

| Symptom                                         | Fix                                                                         |
| ----------------------------------------------- | --------------------------------------------------------------------------- |
| `Unable to locate credentials` / `ExpiredToken` | Run `aws login`                                                             |
| MCP server won't start (`uvx` not found)        | Run `devbot install` (installs `uv`), ensure `~/.local/bin` is on PATH      |
| Wrong region in MCP                             | Set `aws_region` in `.devbot.project.jsonc`, or `AWS_REGION` env            |
| Skills missing                                  | `devbot module install` (clones the toolkit repo), then re-init the project |
