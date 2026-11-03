---
date: 2026-11-03
keywords: ["github", "copilot", "review-request", "requestReviews", "botIds"]
aliases: ["request copilot review", "copilot reviewer not a collaborator", "add copilot as reviewer"]
---

## Request a Copilot review with GraphQL `requestReviews` and `botIds`

The working call passes the Copilot bot's node id to the GraphQL mutation:

```bash
PR_ID=$(gh api graphql -f query='query { repository(owner:"O", name:"R") { pullRequest(number:N) { id } } }' \
  --jq '.data.repository.pullRequest.id')

gh api graphql -f query="mutation { requestReviews(input: {pullRequestId: \"$PR_ID\", botIds: [\"BOT_kgDOCnlnWA\"]}) { pullRequest { reviewRequests(first:5) { nodes { requestedReviewer { __typename ... on Bot { login } } } } } } }"
```

It answers `{"__typename":"Bot","login":"copilot-pull-request-reviewer"}` and the review lands a few minutes later.

What silently fails: `gh pr edit <pr> --add-reviewer copilot-pull-request-reviewer` exits 0 and registers nothing — `reviewRequests` stays `[]` — and the REST `POST /repos/{o}/{r}/pulls/{n}/requested_reviewers` answers `422 Reviews may only be requested from collaborators`, because Copilot is a GitHub App bot rather than a collaborator. Note the two different ids: `users/copilot-pull-request-reviewer` resolves to an Organization node (`O_…`, wrong for `botIds`), while `users/Copilot` resolves to the Bot node `BOT_kgDOCnlnWA`.

Verify the request registered by reading `reviewRequests` back; a push alone does not re-trigger a review, so every round of the fix-and-review loop needs its own request.
