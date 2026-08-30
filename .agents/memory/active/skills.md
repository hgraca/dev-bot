---
tags: [bootstrap, session, skills]
description: Context skills that must be preemptively loaded for correct agent behavior
---

## Preemptive Context Skill Loading

The agent must preemptively load the git commit context skills — `devbot:git-conventional-commits` and `devbot:git-atomic-commits` — at the start of every session. These inform all git work (commit messages, staging, branching); without them the agent may violate project git conventions.

Load the `devbot:git-conventional-commits` context skill before writing any commit message and the `devbot:git-atomic-commits` context skill before staging — never commit without them.
