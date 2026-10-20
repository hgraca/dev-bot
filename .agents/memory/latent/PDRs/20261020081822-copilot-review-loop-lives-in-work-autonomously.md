---
date: 2026-10-20
keywords: ["copilot", "gh-create-pr", "work-autonomously", "review-loop"]
---

## The Copilot review loop lives in work-autonomously, not gh-create-pr

`devbot:gh-create-pr` is scoped to opening a pull request: title, body, base, and the reviewer
request. The wait/re-check loop, effort handling, finding retrieval, fixups, and comment marking
belong to `devbot:work-autonomously`, the command that runs an assignment end to end. `gh-create-pr`
keeps only `--reviewer @copilot` plus a one-line pointer. PR creation is a bounded interactive step;
the review loop can run for hours and writes fixes, so it needs the autonomous command's mandate and
must not be implied by every PR creation. `devbot:address-review` names `work-autonomously` as the
one exception to its local-only rule.
