---
date: 2026-11-18
keywords: ["github", "mergeStateStatus", "BLOCKED", "reviewDecision", "branch-ruleset"]
trigger-on: ["gh-pr-merge-gate", "gh-review-loop-gate"]
---

## All checks green and MERGEABLE can still be BLOCKED — that is REVIEW_REQUIRED

`gh pr checks --required` returning no non-green rows plus `mergeable: "MERGEABLE"` does not mean the pull request can merge: `mergeStateStatus: "BLOCKED"` is a third, independent gate, and on a repository whose ruleset requires an approving review it means `reviewDecision: "REVIEW_REQUIRED"` — not a failing or pending check. Copilot reviews arrive as `COMMENTED`, which never satisfies that rule, so a fully reviewed bot-approved PR still reads BLOCKED until a human approves. Diagnose before treating BLOCKED as a defect: read `gh pr view <pr> --json reviewDecision,mergeStateStatus,mergeable` and the individual rollup conclusions together; a green rollup with `REVIEW_REQUIRED` is the expected terminal state of the review loop, and the loop must hand off rather than look for a check to fix.
