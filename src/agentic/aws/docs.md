---
title: "AWS"
description: "Work with AWS from an agent through per-project AWS connections — one MCP server per connection, pinned to a named identity."
skills: ["aws"]
commands: ["aws-setup"]
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
| `profile` | the shared AWS config — `~/.aws/config`, or the keys in `~/.aws/credentials`                                                                                                                                     | nothing credential-shaped enters dev-bot config |

Use a `${VAR}` reference for anything secret: a literal value in the config is convenient for non-secret settings, but a literal secret sits in a file.

Declaring both forms is rejected — credential precedence would be ambiguous. An optional `account_id` turns the identity into a _checked_ property: the launcher calls `sts get-caller-identity` and refuses to start when the reported account differs.

## Read-only is an IAM property

The module imposes no read/write restriction; the server exposes the full AWS API surface. Read-only is the IAM policy on the connection's identity — run it as a least-privilege (ideally read-only) role. The connection pin covers the **MCP path only**: an agent with shell access can reach AWS directly with whatever credentials the machine holds, so least privilege plus a permission boundary (or SCP) is the control that actually holds.

## Setting up the identity

Read-only access is an IAM property, so the identity has to exist before a connection can use it. The steps below produce one IAM **user** with a key pair — the AWS equivalent of a service account. (A **role** has no keys of its own; it is assumed. To use that model instead, give the connection a `profile` with `role_arn` + `source_profile` rather than an `env` block.)

**1. Create the policy.** IAM → _Policies_ → _Create policy_ → **JSON**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AwsConfigRead",
      "Effect": "Allow",
      "Action": ["eks:ListClusters", "eks:DescribeCluster", "eks:ListNodegroups", "eks:DescribeNodegroup", "eks:ListUpdates", "eks:DescribeUpdate", "eks:ListAddons", "eks:DescribeAddon", "eks:DescribeAddonVersions", "eks:ListIdentityProviderConfigs", "eks:DescribeIdentityProviderConfig", "ec2:Describe*", "rds:Describe*", "rds:ListTagsForResource", "elasticache:Describe*", "elasticache:ListTagsForResource", "es:ListDomainNames", "es:DescribeDomains", "es:DescribeDomainConfig", "es:ListTags", "s3:ListAllMyBuckets", "s3:GetBucket*", "s3:GetAccountPublicAccessBlock", "tag:GetResources"],
      "Resource": "*"
    },
    {
      "Sid": "S3DataRead",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:ListBucketVersions", "s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging"],
      "Resource": ["arn:aws:s3:::REPLACE-WITH-BUCKET", "arn:aws:s3:::REPLACE-WITH-BUCKET/*"]
    },
    {
      "Sid": "OpenSearchDataRead",
      "Effect": "Allow",
      "Action": ["es:ESHttpGet", "es:ESHttpHead", "es:ESHttpPost"],
      "Resource": "arn:aws:es:eu-central-1:REPLACE-ACCOUNT-ID:domain/REPLACE-DOMAIN-NAME/*"
    },
    {
      "Sid": "OpenSearchServerlessRead",
      "Effect": "Allow",
      "Action": ["aoss:ListCollections", "aoss:BatchGetCollection", "aoss:APIAccessAll"],
      "Resource": "*"
    }
  ]
}
```

Narrow `S3DataRead` to the buckets you actually need — as written it reads every object in the account. `aoss:APIAccessAll` must stay `"*"`. `es:ESHttpPost` is there because OpenSearch clients send searches as POST; it is method-wide, so the domain-side gate in step 5 is what actually keeps the access read-only. Drop the Serverless statement unless you use OpenSearch Serverless.

**2. Create the group and the user.** IAM → _User groups_ → create `devbot` and attach the policy. Then IAM → _Users_ → create e.g. `devbot-readonly` with **no console access**, and add it to that group. The group is what the key inherits, so members can rotate without touching permissions.

**3. Create the access key.** Open the user → _Security credentials_ → _Access keys_ → _Create access key_ → **"Application running outside AWS"**. The use case only changes the console's guidance; the key pair is identical whichever you pick (the exception is _"running on an AWS compute service"_, which offers a role instead — never hold static keys on a workload that can assume one). Copy the **Access key ID** and the **Secret access key**; the secret is shown once, and a user can hold at most two keys.

**4. Hand the values to the connection.** Put them in the repo-root `.env` (gitignored — the launcher and the `datasources` renderer both load it) under the names the connection references:

```bash
AWS_PROD_RO_ACCESS_KEY_ID=AKIA…
AWS_PROD_RO_SECRET_ACCESS_KEY=…
```

**5. OpenSearch needs a second gate.** IAM permission alone is not enough: the domain must allow the principal too. Add the user (or the group) to the domain's **access policy**, or — with fine-grained access control, which is what makes this genuinely read-only despite `es:ESHttpPost` — map it to a **backend role** with read-only index permissions. A correct IAM policy that still returns 403 on search almost always means this step is missing.

**The copied rules file is local, and only on an enabled module.** `init.sh` fetches AWS's own `aws-agent-rules.md` into the project's devbot dir (`<devbot_dir>/memory/active/`), but only when the `aws` module is **enabled for that project** — it is machine-local bootstrap content, not project source. It is listed in the project's `.git/info/exclude` under a `DEVBOT - aws` block, so it never enters the project's history.

## Configuration

| Key               | Where                   | Meaning                                                                                                                              |
| ----------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `aws_connections` | `.devbot.global.jsonc`  | catalogue of connections — a name mapped to `region`, plus `env` (values or `${VAR}`) **or** `profile`, and an optional `account_id` |
| `aws_connections` | `.devbot.project.jsonc` | list of connection names this project opts into                                                                                      |

A connection that is declared but not selected is not wired; a selected connection that is not declared is **not wired either** — it warns and is skipped, since a manifest for it would register a server that cannot start.

Each generated `opencode` manifest ships the server with `enabled: false` (wired but not started), matching the other gateway modules — flip it to `true` in `opencode.jsonc` to start it, or toggle it in the harness.

`install.sh` installs the AWS CLI, `uv` and the `mcp-proxy-for-aws-cli` uv tool, and fetches AWS's agent rules. `up.sh` verifies each declared connection's credentials and pinned account, and never logs in.

## See also

- [MCP configuration](/mcp-config) — the manifest schema and per-harness wiring
- [Datasources](/modules/agentic/datasources) — database and Redis data access
