---
date: 2026-11-25
keywords: ["devbot", "pr-watch", "no-fixup", "review-loop", "wait"]
aliases: ["pr-watch exit 3", "review loop wait primitive", "no-fixup blocks the wait"]
---

## `pr-watch` cannot be the review loop's wait primitive while fixups exist

`pr-watch` answers with an exit code, and `3` means "a required check failed". In this repository
`no-fixup` is a required check and is **red by design** until the fixups are squashed, so every
`pr-watch` call returns `3` immediately — observed on dev-bot #191 with `0 poll(s)`: it bailed before
a review could ever land, and the review loop's documented Wait step became a no-op that looked like
a failing check.

`devbot:gh-review-loop` already excludes the fixup guard from its own Gate ("a no-fixup guard is not
a failure"), but that exclusion is not taught to `pr-watch`. Two workarounds that work today: wait on
the review count instead (`gh api --paginate repos/<o>/<r>/pulls/<n>/reviews --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | length'`, looping until it increments), or poll `gh pr checks` for `pending == 0` and then read the review separately. Both are hand-rolled; the durable fix is an ignore-check option on `pr-watch`.

Related correction, learned across four loops: the review body's **summary paragraph drifts** from
its own counts. It can claim "critical issues remain" while the `<details>` blocks enumerate none —
seen on dev-bot #184 round 4, #185 round 5 and #191 round 4. Trust the structured counts (`N open
issues`, `N previously missed issues`) over the prose sentence; the prose is generated separately and
is not reconciled with the findings list.
