---
date: 2026-11-22
keywords: ["github", "copilot-review", "timeline", "stale-request", "head-commit"]
aliases: ["already requested", "review cursor", "requested_reviewers"]
---

## A review request is only pending if it is newer than the PR head

GitHub's timeline keeps a `review_requested` event forever, so "a request exists" is not "this head is queued". After a push, a tool that checks mere historical presence returns *already requested* and never asks for a review of the new code — the quiet failure mode that leaves a PR unreviewed. Bound the check by the head: fetch the PR's last commit date (`gh pr view --json commits --jq '.[-1].committedDate'`) and treat the request as pending only when its `created_at` is at or after it; otherwise re-request. Two related traps in the same area: `--json reviewRequests` and the REST `requested_reviewers` view never list bot reviewers, so the timeline is the only honest source; and the reviews endpoint mixes human and bot reviews and is paginated, so selecting `.[-1]` can end a wait on a human's comment or miss a Copilot review on a later page. Filter to the Copilot login and to reviews submitted after the request cursor.
