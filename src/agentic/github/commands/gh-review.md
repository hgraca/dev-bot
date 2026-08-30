---
name: devbot:gh-review
description: Review a GitHub PR and address its review comments locally
---

Review the GitHub PR at the URL given below and address its review comments locally. Never post replies, comments, or resolutions back to GitHub.

PR URL: $ARGUMENTS

If no PR URL is provided, ask the user for the PR URL before proceeding.

## Steps

1. Parse the PR URL to extract `{owner}`, `{repo}`, and the PR number.
2. Read the PR review comments using the `gh` CLI. Prefer `--json` output piped through `cat` to avoid shell-piping truncation:
    - `gh pr view <PR> --json title,body,state,comments`
    - `gh api repos/{owner}/{repo}/pulls/<PR>/comments` — line-anchored review comments (most relevant)
    - `gh api repos/{owner}/{repo}/pulls/<PR>/reviews` — top-level review summaries
3. Use the `git` CLI to verify you are on the branch associated with the PR. Switch if needed.
4. Load the `devbot:address-review` context skill and follow it to address each review comment one at a time.
