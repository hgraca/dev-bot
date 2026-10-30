---
date: 2026-10-30
keywords: ["github", "copilot", "review_requested", "timeline", "requestReviews"]
aliases: ["verify copilot review request", "review request cursor", "copilot_work_started"]
trigger-on: ["copilot-review-rerequest", "copilot-review-verification"]
---

## Verify a Copilot review request with a timeline event-id cursor, not an exit code or a timestamp

`gh pr edit <pr> --add-reviewer @copilot` exits 0 whether or not it registers anything, so the only
evidence is the PR timeline: after the request, `review_requested` with `requested_reviewer.login`
`Copilot` (capital C) or a `copilot_work_started` event must appear. Take the **cursor before**
requesting — the maximum event `id` among those two event types — and require a matching event with
a greater `id`; a whole-second `date` baseline rejects a legitimately same-second event, and "any
such event exists" is satisfied by an earlier round on a re-review. Re-capture the cursor immediately
before the GraphQL fallback too, because the mutation's own event can land before a later timestamp.

The fallback must be executable: `requestReviews` needs declared variables and `-f` bindings —
`gh api graphql -f query='mutation($pr:ID!,$bot:ID!){ requestReviews(input:{pullRequestId:$pr, botIds:[$bot]}) { pullRequest { id } } }' -f pr="$PR" -f bot="$BOT"`
with `PR="$(gh pr view <pr> --json id --jq .id)"` and
`BOT="$(gh api '/users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id)"`. The mutation parses
and binds correctly if a bogus id fails only with "Could not resolve to a node with the global id".
