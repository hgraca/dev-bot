---
date: 2026-11-04
keywords: ["gh", "copilot", "code-review", "pull-request"]
---

# Request Copilot's review after the PR exists, never on `gh pr create`

## The trap

`gh pr create --reviewer @copilot` aborts the whole creation when the reviewer cannot be resolved (`could not request reviewer: '@copilot' not found`), leaving no PR to repair. A rejected reviewer is not a recoverable per-reviewer failure on that command.

## The rule

Create the PR without `--reviewer`, then request the review with `gh pr edit <url> --add-reviewer @copilot`.

## Verifying the request registered

`gh pr edit` and `gh pr create` can both exit 0 without queueing it, and `--json reviewRequests` does not list bot reviewers. The signal is a `review_requested` event whose reviewer is `Copilot` in the PR timeline — paginate it (`gh api --paginate …/issues/<n>/timeline`), because the event can be past the first page. For the GraphQL fallback, resolve the bot node id from `gh api 'users/copilot-pull-request-reviewer%5Bbot%5D' --jq .node_id` (a new PR has no prior review to read it from) and the PR id from `gh pr view <url> --json id`; then re-read the timeline and require a newer event before treating the request as queued.
