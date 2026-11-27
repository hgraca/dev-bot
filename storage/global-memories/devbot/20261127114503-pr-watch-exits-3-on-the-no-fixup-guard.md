---
date: 2026-11-27
keywords: ["devbot", "pr-watch", "review-loop", "fixup"]
trigger-on: ["gh-review-loop", "pr-watch"]
---

## `pr-watch` exits 3 on the no-fixup guard, which is red by design mid-loop

While a review loop is running, the branch intentionally carries `fixup!` commits, and the
`No fixup! commits` check is a **required** check. `pr-watch` treats any failed required check as
exit 3 and stops, so it cannot be used to wait for the next review between a fixup push and the
squash. Its output says `checks: fail` and reports no review, which reads like a real problem.

Wait for the review with GitHub's own watcher instead:

```bash
gh event listen --resource https://github.com/<owner>/<repo>/pull/<n> \
  --event com.github.pull_request.review.submitted.v1 --timeout 30m
```

The guard goes green on the push that publishes the squash, so it is not a gate to satisfy early.
`pr-watch` remains the right tool before any fixup exists, and after the squash.
