---
date: 2026-10-01
keywords: ["git", "github", "copilot", "pull-request", "code-review"]
trigger-on: ["copilot-code-review", "gh-pr-create-reviewer"]
---

## Copilot code review's effort level cannot be set from the CLI

GitHub Copilot code review runs at one of two **effort levels** — **Lite** (fast, targeted feedback
on bugs, security and style; the default) and **Balanced** (a higher-reasoning model for complex,
security-sensitive or cross-service changes). `gh pr create --reviewer @copilot` — or
`gh pr edit <n> --add-reviewer @copilot` on an existing PR — requests the review, but the effort
level is chosen in the pull request's **Reviewers panel on GitHub.com**; the CLI has no flag for it
(`cli/cli#12921` tracks the request). Requesting Copilot from the CLI therefore gets whatever the
organization or repository default is, which is Lite unless it has been overridden. Confirm the level
in the UI once the PR is open when review depth matters. The REST equivalent is requesting
`copilot-pull-request-reviewer[bot]` as a reviewer.
