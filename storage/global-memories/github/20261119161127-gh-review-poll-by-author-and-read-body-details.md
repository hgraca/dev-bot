---
date: 2026-11-19
keywords: ["github", "copilot", "review", "gh-api", "pull-request"]
trigger-on: ["gh-review-loop", "copilot-review-polling"]
---

## Poll reviews by author and id, and read the review body's details blocks

Two traps when iterating a Copilot review loop with `gh`.

**Counting reviews is not a landing signal.** Replying to a review thread creates
a review object authored by *you*, so `gh api …/pulls/<n>/reviews` grows after
your own replies and a naive `length > 1` poll reports "review landed" on your
own comment. Filter by author and by id above the cursor captured before the
request: `[.[] | select(.user.login | test("copilot"; "i")) | select(.id > $cursor)]`.

**A review's findings are not all threads.** Copilot enumerates findings in the
review body as collapsible `<details>` blocks headed `N open issues`,
`N previously missed issues` and `N resolved since last review`. A round can
report `0 open issues` with a fully resolved thread list and still carry
unaddressed `previously missed` entries, which have no thread to reply to or
resolve — their resolution goes on the pull request as a plain comment. Trust the
body's own counts over the thread list before declaring the round converged.
