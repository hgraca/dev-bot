---
date: 2026-11-25
keywords: ["github", "copilot", "review", "ccr-overview"]
see: ["learnings/20261021100201-copilot-review-previously-missed-issues.md"]
---

## A Copilot `ccr-overview-v2` body can name findings in prose with no itemisable sections

Some Copilot review bodies carry only `<!-- ccr-overview-v2 -->`, a one-line verdict, and "**No open issues** 🎉" — no `N open issues` / `previously missed` `<details>` blocks and no inline threads. The verdict line still names the mechanisms it objects to ("stale success stamps", "failed retries"), so treat that prose as the finding list and fix it, but do not expect the body to converge: five consecutive rounds on one pull request kept that shape while each named mechanism was closed, and `gh pr checks`/% was the only objective signal. Close such a loop on the body's own count ("No open issues" with no unaddressed sections) once the prose has been addressed and the required checks are green — chasing the summary wording forever never produces an itemised finding.
