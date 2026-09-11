---
name: devbot:gh-make-review
description: Check out a GitHub PR and code-review its changeset locally
---

Code-review the GitHub PR at the URL below. All review output stays local — never post reviews, comments, or any other write back to GitHub.

PR URL: $1

If no PR URL is provided, ask the user for the PR URL before proceeding.

## Steps

1. Parse the PR URL to extract `{owner}`, `{repo}`, and the PR number.
2. Verify the working tree is clean; if it has uncommitted changes, stop and ask how to proceed. Then check out the PR branch with `gh pr checkout <PR>`.
3. Determine the PR base branch with `gh pr view <PR> --json baseRefName`; the changeset under review is `git diff <base>...HEAD`.
4. Ask @reviewer to load the `devbot:review-implementation` and `code-review-and-quality` context skills and review that changeset against the PR base branch, reporting findings with file:line references.
5. Write the full review to `.agents/memory/thinking/<descriptive-name>.md` (per the `devbot:thinking` skill) and summarize the findings in the session.

## Must not

- Never run a GitHub write operation — no `gh pr review`, `gh pr comment`, no mutating `gh api` call. The review stays local.
