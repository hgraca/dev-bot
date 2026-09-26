---
name: devbot:aws-setup
description: Set up AWS for dev-bot — install the prerequisites and declare connections with static credentials
---

# AWS Setup

The `aws` module installs its prerequisites and never prompts. What it cannot do
is create your credentials — declare those as **connections**.

## 1. Install the prerequisites

```bash
devbot install          # unzip, uv, AWS CLI v2, AWS agent rules
```

The launcher runs the proxy through `uvx`, so `uv` and the AWS CLI must be on
`PATH` (`~/.local/bin`).

## 2. Provide credentials

Either a profile in `~/.aws/config` — ideally an assume-role over a source key
that can only `sts:AssumeRole` the read-only role:

```ini
# ~/.aws/config
[profile aws-prod-ro]
role_arn       = arn:aws:iam::<account-id>:role/ReadOnlyAgent
source_profile = gete-source
region         = eu-central-1
```

```ini
# ~/.aws/credentials — the only long-lived secret
[gete-source]
aws_access_key_id     = ...
aws_secret_access_key = ...
```

or the `env` form, which keeps the keys out of `~/.aws` entirely.

## 3. Declare the connection

```jsonc
// .devbot.global.jsonc
"aws_connections": {
  "aws-prod-ro": {
    "region": "eu-central-1",
    "account_id": "123456789012", // optional — asserted at launch
    "profile": "aws-prod-ro"
    // instead of profile, supply credentials directly:
    // "env": {
    //   "AWS_ACCESS_KEY_ID": "${AWS_PROD_RO_KEY_ID}",
    //   "AWS_SECRET_ACCESS_KEY": "${AWS_PROD_RO_SECRET}"
    // }
  }
}
```

`profile` and `env` are **mutually exclusive**. In the `env` form the values may
be literals or `${VAR}` references; put the values in the repo-root `.env` or
your shell, since dev-bot writes no secret into any config.

## 4. Opt the project in

```jsonc
// .devbot.project.jsonc
"aws_connections": ["aws-prod-ro"]
```

Then re-init:

```bash
devbot init <project>   # or a bare `devbot` start
```

## 5. Verify

```bash
devbot up               # verifies every declared connection; never logs in
```

## Notes

- `devbot up` checks each declared connection with `sts get-caller-identity` and
  reports failures — it never opens a browser.
- `account_id` is enforced: a key resolving to another account refuses to start
  the server.
- Skills arrive via the `agent-toolkit-for-aws` external module; the agent rules
  land in `.agents/memory/active/aws-agent-rules.md`.
- Read-only is an IAM property of the connection's identity; the connection pin
  covers the MCP path only.
