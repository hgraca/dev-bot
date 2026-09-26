---
title: "AWS"
description: "Work with AWS from an agent through per-project AWS connections — one MCP server per connection, pinned to a named identity."
skills: ["aws"]
---

Work with AWS from an agent: inspect and manage resources, chain API calls in a sandboxed script, search AWS documentation, and load curated AWS skills — through AWS's managed **AWS MCP Server**, one instance per configured connection.

## What it does

Ships one skill (`devbot:aws`), vendors AWS's own `agent-toolkit-for-aws` skills, and wires the AWS MCP Server into the harness — **one server per connection**, named `aws-<connection>`.

An AWS **connection** is a named identity plus a region. Connections are declared once in `.devbot.global.jsonc` and each project opts in by name, so a machine can hold several AWS identities (a production read-only one, a dev one, another account) and a project sees only the ones it selected. `devbot init`/`reinit` wires and prunes the servers, and nothing is prompted at install time.

## Credentials

Authentication is **non-interactive**: no `aws login`, no `aws sso login`, no browser.

| Form      | Where the keys live                                                                                                                                                                                              | Note                                            |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `env`     | values, or `${VAR}` references the launcher resolves from the shell environment and the repo `.env`, handed to the server process through its **environment** (never the command line, which is visible in `ps`) | fixes the identity to that exact key pair       |
| `profile` | `~/.aws/config`                                                                                                                                                                                                  | nothing credential-shaped enters dev-bot config |

Declaring both is rejected — credential precedence would be ambiguous. An optional `account_id` turns the identity into a _checked_ property: the launcher calls `sts get-caller-identity` and refuses to start when the reported account differs.

## Read-only is an IAM property

The module imposes no read/write restriction; the server exposes the full AWS API surface. Read-only is the IAM policy on the connection's identity — run it as a least-privilege (ideally read-only) role. The connection pin covers the **MCP path only**: an agent with shell access can reach AWS directly with whatever credentials the machine holds, so least privilege plus a permission boundary (or SCP) is the control that actually holds.

## Configuration

| Key               | Where                   | Meaning                                                                                                                              |
| ----------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `aws_connections` | `.devbot.global.jsonc`  | catalogue of connections — a name mapped to `region`, plus `env` (values or `${VAR}`) **or** `profile`, and an optional `account_id` |
| `aws_connections` | `.devbot.project.jsonc` | list of connection names this project opts into                                                                                      |

A connection that is declared but not selected is not wired; a selected connection that is not declared warns on init.

`install.sh` installs the AWS CLI and `uv` and fetches AWS's agent rules. `up.sh` verifies each declared connection's credentials and pinned account, and never logs in.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [Datasources](/modules/agentic/datasources) — database and Redis data access
