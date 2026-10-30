---
date: 2026-10-30
keywords: ["devbot", "gh-cli", "copilot-review", "graphql"]
aliases: ["gh pr view reviews empty", "copilot review not found"]
---

## `gh pr view --json reviews` can return an empty list while reviews exist

On `GET-E/dev-bot#40` (2026-10-30) `gh pr view --json reviews` and
`gh api repos/<owner>/<repo>/pulls/<n>/comments` both returned empty for over
ten minutes while four Copilot review threads were live on the PR page. Three
separate REST checks disagreed with what the human could see. `gh api graphql`
answered correctly every time:

```sh
gh api graphql -f query='{ repository(owner:"O", name:"R") { pullRequest(number:N) {
  reviews(last:1){ nodes { submittedAt body } }
  reviewThreads(first:60){ nodes { isResolved path line comments(first:1){ nodes { body } } } }
} } }'
```

Two rules follow. Read reviews through GraphQL when a loop has to observe a
reviewer — the REST endpoints also split inline comments from review bodies, so
"0 comments" is not evidence of no findings. And when a human reports comments
that the API denies, believe the human and switch transports before concluding
the reviewer stalled.
