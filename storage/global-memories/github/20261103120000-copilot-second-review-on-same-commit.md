---
date: 2026-11-03
keywords: ["github", "copilot", "code-review", "pull-request"]
aliases: ["copilot review loop", "clean review then findings", "requested_reviewers empty"]
---

## Copilot posts a clean review, then a substantive one on the same commit

A Copilot code review reporting zero comments is not a verdict: on the same head commit it can post a 0-comment review and then a second review carrying findings 11 minutes, 23 minutes, or 2h40m later. Treating the first as final ended a review loop early four times in one PR (dev-bot #45, 19 findings over 7 rounds). Wait for a second review on the same `commit.oid` before declaring clean, and expect the gap to grow when Copilot is backlogged. Two related traps: the REST `requested_reviewers` field omits bots, so a successful request looks like a no-op — verify with GraphQL `pullRequest.reviewRequests { requestedReviewer { ... on Bot { login } } }`; and request the bot as `reviewers[]=copilot-pull-request-reviewer[bot]`, because the login without `[bot]` is rejected with "Reviews may only be requested from collaborators".
