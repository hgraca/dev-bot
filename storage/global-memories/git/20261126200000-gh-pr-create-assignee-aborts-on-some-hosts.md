---
date: 2026-11-26
keywords: ["git", "gh-pr-create", "assignee", "github-enterprise"]
aliases: ["--add-assignee", "self-assign pull request", "@me"]
trigger-on: ["gh-pr-create-assignee", "gh-pr-create-post-create-steps"]
see: ["git/20261020081823-copilot-review-request-create-fails-graphql-botids.md"]
---

## `gh pr create --assignee` aborts the creation on hosts that resolve the login first

On github.com (gh 2.103.0) `api.CreatePullRequest` runs the `createPullRequest` mutation first and applies assignees afterwards, returning the pull request together with the error — so `gh pr create --assignee <rejected-login>` still creates the PR, prints its URL and exits 1. On GitHub Enterprise Server the logins are resolved to IDs before the create (`could not assign user: …`), so the same command creates nothing at all. Any instruction that promises "a failed assignment costs only the assignment" must therefore never put `--assignee` on `gh pr create`: create the pull request, then run `gh pr edit <url> --add-assignee @me`. It is the same shape as the `--reviewer` trap — a post-create step does not belong on the create command, because there is no pull request to repair when it fails.
