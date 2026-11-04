---
name: devbot:gh-pr-loop
description: Loop GH PR Copilot code reviews and fixes until Copilot approves
---

Given a pull request for the PR in context (if no PR is in context ask what PR the user means),

- if the PR does not have a Copilot CR requested, request one 
- wait for it to land using a sleep in a PTY (sleep for 1m at a time until the CR lands, up to 1h)
- fix the issues as fixups
- push
- ask Copilot for another review
- repeat until Copilot doesn't find any more unresolved issues worth solving

When the loop finishes, squash the fixup commits 
and notify the user that the work is done and the user needs to force-push.
