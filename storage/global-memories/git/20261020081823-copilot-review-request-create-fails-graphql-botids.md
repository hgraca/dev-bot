---
date: 2026-10-20
keywords: ["git", "github", "copilot", "review-request", "graphql"]
aliases: ["@copilot not found", "copilot-pull-request-reviewer", "requestReviews botIds"]
supersedes: ["git/20261019171304-copilot-review-request-needs-graphql-botids.md"]
---

## `gh pr create --reviewer @copilot` can abort; request the bot with GraphQL `botIds`

On `gh` 2.86.0, `gh pr create --reviewer @copilot` failed with `could not request reviewer:
'@copilot' not found` and created no PR at all, while `gh pr edit <n> --add-reviewer @copilot`
returned 0 and still left `pulls/<n>/requested_reviewers.users` empty with no review started. The
reviewer is the bot `copilot-pull-request-reviewer[bot]` (login `Copilot`). The reliable path is
GraphQL: resolve `gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id` and the PR
node id (`gh api repos/{owner}/{repo}/pulls/<n> --jq .node_id`), then call
`requestReviews(input:{pullRequestId:<pr>,botIds:[<bot>]})`; the response lists the bot under
`reviewRequests` and the review lands in roughly 3–6 minutes. Create the PR without the flag when it
fails, request via GraphQL, and re-request explicitly after every push — Copilot does not re-review
on its own.
