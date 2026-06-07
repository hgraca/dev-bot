---
tags: [bootstrap, session, skills]
description: Skills that must be preemptively loaded for correct agent behavior
---

## Preemptive Skill Loading

The agent must preemptively load the git commit skills — `git-conventional-commits` and `git-atomic-commits` — at the start of every session. These inform all git work (commit messages, staging, branching); without them the agent may violate project git conventions.

Load `git-conventional-commits` before writing any commit message and `git-atomic-commits` before staging — never commit without them.
