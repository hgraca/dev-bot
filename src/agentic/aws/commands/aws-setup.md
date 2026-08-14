# AWS Setup (manual fallback)

Run these steps by hand when `devbot install` was non-interactive (no TTY) or
an interactive step was skipped. Idempotent — safe to re-run.

## 1. Install prerequisites

```bash
# uv (for the AWS MCP proxy)
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
```

## 2. Install the AWS CLI v2

```bash
curl -fsSL 'https://awscli.amazonaws.com/v2/install.sh' | bash
export PATH="$HOME/.local/bin:$PATH"
aws --version   # verify
```

## 3. Set the default region

```bash
aws configure set region <region>   # e.g. us-east-1
```

## 4. Authenticate

```bash
aws login --region <region>
```

A browser window opens. Credentials are valid 12 hours and renewable for
90 days without re-authenticating.

Verify:

```bash
aws sts get-caller-identity
```

## 5. Configure the Agent Toolkit (skills + MCP for detected agents)

```bash
aws configure agent-toolkit --region us-east-1
```

Interactive wizard (~30s). The toolkit service is only in `us-east-1`.

Verify:

```bash
aws agent-toolkit list-available-skills --region us-east-1
```

## 6. Install skills for this project

```bash
devbot module install     # clones agent-toolkit-for-aws into vendor/
devbot init <project>     # wires skills + MCP launcher + rules into the project
```

## 7. Save the agent rules

The module does this automatically during `devbot init` (fetches
`aws-agent-rules.md` into the project's `.agents/memory/active/`). To fetch it
manually:

```bash
curl -fsSL https://raw.githubusercontent.com/aws/agent-toolkit-for-aws/refs/heads/main/rules/aws-agent-rules.md \
  -o .agents/memory/active/aws-agent-rules.md
```

## Notes

- On every `devbot` / `devbot up`, the module checks auth and triggers
  `aws login` if the session has expired.
- Per-project region override: add `"aws_region": "<region>"` to
  `.devbot.project.jsonc`.
