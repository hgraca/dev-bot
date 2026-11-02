---
date: 2026-11-02
keywords: ["devbot", "copilot-review", "pull-request", "gh"]
---

## Requesting and looping a GitHub Copilot code review

`gh pr create … --reviewer @copilot` or `gh pr edit <n> --add-reviewer @copilot` requests GitHub Copilot code review, but neither a zero exit nor `gh pr view --json reviewRequests` proves it registered — confirm a `ReviewRequestedEvent` for `copilot-pull-request-reviewer[bot]` in the PR timeline (GraphQL `timelineItems(itemTypes:[REVIEW_REQUESTED_EVENT])`). A Lite-effort review typically posts in 3–5 minutes, and the verdict arrives as a review body plus optional inline threads. Re-request after each push that answers findings; with no new commits it may decline to run again, so a push or a comment is what wakes it.

Per-finding threads are GraphQL: reply with `addPullRequestReviewThreadReply`, then `resolveReviewThread`, both keyed by the thread id from `reviewThreads`. A finding that exists only in the review body has no thread, so post its resolution as a PR comment in the same bullet format. The overview re-lists resolved findings as "resolved since last review", and the loop ends when a new review reports "No open issues".
