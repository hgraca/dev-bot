---
date: 2026-06-17
keywords: ["signoz", "skills", "npx", "--yes", "tui"]
---

## skills add --yes flag required to suppress interactive TUI selector

The SigNoz `skills` CLI shows an interactive "Select skills to install" TUI even when invoked via `npx --yes`. The `--yes` flag must be passed directly to the `skills add` subcommand — `npx --yes` alone does not suppress the selector. Correct invocation: `npx --yes skills add --yes SigNoz/agent-skills`. Without the subcommand-level `--yes`, the TUI blocks non-interactive installs (CI, automated dev-bot module installation). The `--yes` to `skills add` causes it to install ALL skills rather than presenting the picker.
