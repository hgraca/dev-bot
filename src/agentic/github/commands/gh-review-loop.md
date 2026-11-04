---
name: devbot:gh-review-loop
description: Loop Copilot pull-request reviews and fixes until a review introduces no new findings
---

Run the Copilot review loop for the pull request below.

PR: $ARGUMENTS

If no PR is given and none is in context, ask which pull request the user means.

Load the `devbot:gh-review-loop` skill and follow it to the end — it carries the request/verify
mechanics, the wait cadence, and the read/fix/mark/track steps. Stop when a review introduces no new
findings, squash the fixups, and tell the user to run the force-push command. Never merge.
