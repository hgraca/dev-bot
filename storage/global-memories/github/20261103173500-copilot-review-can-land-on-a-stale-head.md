---
date: 2026-11-03
keywords: ["github", "copilot", "force-push", "stale-review", "commit_id"]
aliases: ["copilot reviewed the old commit", "review on previous head", "stale copilot findings"]
---

## After a force-push, a Copilot review can land on the previous head

Requesting a review on a force-pushed branch does not guarantee it reviews the current head: the review carries the commit it was actually generated from, and that can be the pre-push SHA. Observed on GET-E/dev-bot#50 — the fourth review was recorded against `5bdf017` while the PR head had already moved to `e569bc19`, so it re-raised a finding that was fixed on the newer head and added three false positives about the new code.

Check `commit_id` before acting on findings:

```bash
gh api repos/O/R/pulls/N/reviews --jq '.[] | "\(.commit_id[0:7]) \(.state) \(.body|length)"'
gh pr view N --json headRefOid --jq .headRefOid[0:7]
```

When they differ, answer the threads with evidence and re-request rather than editing code to satisfy a finding the reviewed commit no longer contains — and say plainly which commit each finding applies to, so the next reader does not take the stale one at face value. A review's own headline can also contradict its body (seen: "No open issues 🎉" alongside "2 previously missed issues"); trust the enumerated findings, not the summary line.
