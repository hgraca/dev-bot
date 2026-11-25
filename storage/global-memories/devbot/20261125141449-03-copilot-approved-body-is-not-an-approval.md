---
date: 2026-11-25
keywords: ["devbot", "copilot", "review-decision", "pull-request"]
aliases: ["approved body", "REVIEW_REQUIRED", "mergeStateStatus BLOCKED"]
---

## A Copilot review body can say "Approved" while the decision stays REVIEW_REQUIRED

Copilot's review body is its own summary: `### 🟢 Approved` with `**No open issues**` can arrive on a review submitted as `COMMENTED`, so the pull request's `reviewDecision` stays `REVIEW_REQUIRED` and `mergeStateStatus` stays `BLOCKED` even though every check is green. Judge the gate on `gh pr view --json reviewDecision,mergeStateStatus`, never on the body text — and do not re-request a review to "convert" it, because that is farming an approval and a human approval may be what the ruleset wants. `pr-watch` exits 0 on such a review all the same: it treats a landed review as the answer, so the exit code alone never proves the pull request is mergeable.
