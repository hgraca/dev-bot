---
date: 2026-10-24
keywords: ["copilot", "review", "work-autonomously", "threads"]
---

# A Copilot review's intro prose can name findings the structured sections do not

Copilot review bodies open with a one-line verdict paragraph, then the structured sections (`open issues`, `previously missed issues`, `resolved since last review`, file table). On GET-E/dev-bot#20 and #22 the intro paragraph named concrete findings — "reload can falsely succeed for malformed manifests", "custom fixup! bodies bypass the checklist", "three unresolved moderate issues" — while the structured sections reported **No open issues 🎉**, listed no rows, and carried no inline comments. Zero threads, nothing to reply to or resolve.

## What to do

Treat the structured sections as authoritative. A finding exists only if it has an inline thread or a body row with a file anchor; prose in the intro with neither cannot be addressed and re-requesting usually produces the same boilerplate. Worth a cheap hardening pass if the prose names something concrete (that is how the eval-free lock and the widened Git-message exemption got fixed), but it does not reopen the loop.

## Why it is easy to miss

The intro reads like a verdict, not decoration — and `**No open issues** 🎉` in the same body makes the two contradict each other. Earlier rounds of the same PRs did carry real rows, so the pattern is not "Copilot always empties the sections": read both, decide from the anchors.
