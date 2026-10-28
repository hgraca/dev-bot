---
date: 2026-10-28
keywords: ["github", "copilot", "pull-request", "code-review", "graphql"]
aliases: ["re-request copilot review", "requestReviewsByLogin", "add reviewer copilot fails"]
trigger-on: ["copilot-review-rerequest"]
---

## Re-requesting a Copilot review needs the GraphQL mutation with the bot login

GitHub documents re-requesting a Copilot code review as UI-only ("click the button next to Copilot's name in the Reviewers menu"), and the two obvious programmatic routes both fail silently or loudly. `gh pr edit <pr> --add-reviewer copilot` errors with `GraphQL: Could not resolve user with login 'copilot'`; `POST /repos/{owner}/{repo}/pulls/{n}/requested_reviewers` with `reviewers[]=copilot-pull-request-reviewer[bot]` returns the PR object but leaves `requested_reviewers` empty, so the call looks successful while nothing is queued. What works is the mutation `gh` itself uses internally: `requestReviewsByLogin(input: {pullRequestId: <PR node id>, botLogins: ["copilot-pull-request-reviewer[bot]"]})`. Note the bot logins go in `botLogins`, not `userLogins`. Confirm the request landed by watching for the new review object (`GET /pulls/{n}/reviews`) — `requested_reviewers` is not a reliable signal for bots. Also expect repeated comments: Copilot can restate findings already resolved in an earlier round.
