---
date: 2026-09-28
keywords: ["github", "graphql", "pull-requests", "metrics", "gh-cli"]
trigger-on: ["github-pr-metrics", "gh-api-graphql", "pull-request-statistics"]
---

## Windowed merged-PR metrics in one `gh api graphql` search

To compute per-PR statistics (commit count, additions, deletions, changed files, created→merged span) for every PR merged in a date range, do not list PRs and then fetch each one. A single paginated GraphQL `search` covers the window: `search(query: "repo:O/R is:pr is:merged merged:YYYY-MM-DD..YYYY-MM-DD", type: ISSUE, first: 100, after: $cursor)`, selecting `... on PullRequest { number author { login } createdAt mergedAt additions deletions changedFiles url commits { totalCount } }`. `commits.totalCount` gives the commit count without pulling the commit list, and `pageInfo { hasNextPage endCursor }` drives pagination — one request per 100 PRs, no N+1. Add a sibling `repository(owner: $owner, name: $name) { nameWithOwner }` to the same query: when it returns null the repo is missing or not visible to the token, which an empty `nodes` list would otherwise mask as an identical "no PRs merged". Run it through the authenticated `gh` CLI (`gh api graphql -f query=… -f owner=… -f name=… -f q=…`) so no token handling is needed; GitHub search ranges (`merged:a..b`) are inclusive on both ends.
