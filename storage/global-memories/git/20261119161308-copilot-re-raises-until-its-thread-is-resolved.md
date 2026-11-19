---
date: 2026-11-19
keywords: ["git", "copilot", "review-loop", "review-thread", "resolve"]
aliases: ["copilot keeps raising the same finding", "resolve the review thread", "review loop never converges"]
trigger-on: ["copilot-review-loop", "gh-review-loop"]
---

## A Copilot finding is closed by resolving its thread, not by a PR comment

When Copilot posts a finding it attaches it to a review **thread**. Addressing the code change and answering in a pull-request-level comment leaves the thread open, and the next round re-raises the identical finding even though the fix has shipped — the review body then reads "1 open issue" listing something already corrected, which looks like a loop that never converges.

Reply inside the thread (`POST /repos/{owner}/{repo}/pulls/{pr}/comments/{comment_id}/replies`) and resolve it (`resolveReviewThread` mutation), then push and re-request. Findings that exist only as a row in the review body have no thread — those are answered on the pull request. Telling the two apart matters: check the thread list before deciding where the reply goes, or the loop burns a round per finding.
