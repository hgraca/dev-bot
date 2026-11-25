---
name: devbot:gh-review-loop
description: Loop Copilot pull-request reviews and fixes until a review introduces no new findings
---

Run the review loop for the pull request below, with GitHub Copilot as the reviewer.

PR: $ARGUMENTS

If no PR is given and none is in context, ask which pull request the user means.

Load the `devbot:review-loop` skill for the loop — convergence, the fixup discipline, the answer
rule and the finish — and the `devbot:gh-review-loop` skill for Copilot's mechanics: the GraphQL
request, the timeline verification, `pr-watch`, and how to read a Copilot review. Stop when a round
introduces no new findings and every required check is green with the pull request mergeable, then
squash the fixups and tell the user to run the force-push command. Never merge.
