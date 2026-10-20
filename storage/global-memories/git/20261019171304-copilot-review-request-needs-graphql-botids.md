---
date: 2026-10-19
keywords: ["git", "copilot", "pull-request", "review-request", "graphql"]
aliases: ["request copilot reviewer", "copilot-pull-request-reviewer", "add-reviewer @copilot no-op"]
superseded_by: ["git/20261020081823-copilot-review-request-create-fails-graphql-botids.md"]
---

## Requesting the Copilot code-review bot needs the GraphQL `botIds` mutation

> **Superseded by** `git/20261020081823-copilot-review-request-create-fails-graphql-botids.md` (2026-10-20).

`gh pr edit <n> --add-reviewer @copilot` and the REST `POST /repos/{owner}/{repo}/pulls/<n>/requested_reviewers` with `copilot-pull-request-reviewer[bot]` both return success but register nothing: `requested_reviewers` stays empty and no review starts. Resolve the bot's node id (`gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id`) and the PR node id, then call GraphQL `requestReviews(input: {pullRequestId: <pr>, botIds: [<bot>]})`; the response lists the bot under `reviewRequests` and the review lands within ~6 minutes. A PR that already has an older Copilot review also needs this explicit re-request after each push — the CLI/REST helpers silently no-op every time.
