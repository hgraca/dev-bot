---
date: 2026-10-28
keywords: ["github", "gh", "copilot", "reviewer"]
---

## `gh pr create --reviewer @copilot` can exit 0 and request nothing

`gh pr create --reviewer @copilot` may accept the flag, create the pull request and exit 0 while
registering **no** review request — `gh pr view <pr> --json reviewRequests` comes back empty. Nothing
in the output says the request was dropped, so a workflow that assumes success silently never gets a
review.

Verify every time: after creating the PR, check `reviewRequests`. The reliable path is the GraphQL
`requestReviews` mutation with the bot's node id:

```
gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id   # e.g. BOT_kgDOCnlnWA
gh pr view <pr> --json id --jq .id                                     # PR node id
gh api graphql -f query='mutation { requestReviews(input: {pullRequestId: "PR_…", botIds: ["BOT_…"]}) {
  pullRequest { reviewRequests(first: 5) { nodes { requestedReviewer { __typename … on Bot { login } } } } } } }'
```

A non-empty `reviewRequests` with `login: copilot-pull-request-reviewer` is the only confirmation.
Copilot also never re-reviews on its own — re-request after each push, but only when no review is
already pending.
