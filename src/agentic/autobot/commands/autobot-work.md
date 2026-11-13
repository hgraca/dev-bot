---
name: devbot:autobot-work
description: Work an AutoBot ticket to a pull request, signing every comment.
---

Work the ticket below to an open pull request, following `devbot:auto-dev` as you would for any task,
with `devbot:autobot-mode` for everything the unattended run changes.

Load `devbot:autobot-mode` before anything else.

Ticket: $ARGUMENTS

## Sign every comment (MUST)

Every comment you post — on the Jira ticket or the pull request, in any medium — ends with this line,
alone, as the final line of the body:

```
authored by AutoBot
```

That signature is not decoration: it is how the scheduler tells your replies from a human's. A comment
that carries it is never treated as new feedback, so without it AutoBot answers its own comments and
the ticket loops.
