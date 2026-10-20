---
date: 2026-10-20
keywords: ["git", "github", "copilot", "review-comments", "pagination"]
aliases: ["submitted_at missing", "pull_request_review_id", "track findings not comment ids"]
---

## Copilot review rounds need pagination and finding-level tracking, not comment IDs

When polling a Copilot review loop, fetch **all** pages (`gh api --paginate`): older rounds push
findings past the first page, so a first-page-only read reports a clean review or times out. Review
objects carry `submitted_at`; review comments do not — they have `created_at` and
`pull_request_review_id`. Select the new review by `submitted_at`, then select its bot-authored
comments by `pull_request_review_id`. Findings can live only in the review body (its per-file table)
with no comment thread, so a reply/resolve step must record those in a PR comment instead. Repeated
findings get a fresh comment ID each round while body-only findings have none, so track the
underlying issue and affected code, keeping IDs only for replies and resolutions; stop when a review
adds no new findings.
