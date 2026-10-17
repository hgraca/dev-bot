---
tags: [bootstrap, session, skills]
description: Context skills to preemptively load — dev-bot repo: generic craft and the shared commit rules
---

## Preemptive Context Skill Loading

The agent must preemptively load the following context skills at the start of every session:

- `devbot:software-development` — generic craft hub: code-quality principles, tests-first discipline, and the commit protocol. It in turn preloads only `devbot:git-commits`.
- `devbot:git-commits` — the shared commit rules: subject form, the Problems/Solutions body, and the history-rewrite safety rule; every commit depends on it.

Everything else loads from its trigger, not at session start:

- `devbot:git-conventional-commits` — when wording a commit message
- `devbot:git-atomic-commits` — when splitting or ordering commits
- `devbot:git-fixup-commits` — when correcting a branch commit
- `devbot:makefile` — when running or changing `make` targets
- `devbot:documentation-rules` — when writing or editing docs
- `customize-opencode` — when editing opencode/claudecode config, agents, skills, tools, or hooks

The previous eight-entry list was loaded every session; `customize-opencode` (avg 2.00),
`makefile` (2.45) and the three git-technique skills were largely unused per session. Keeping only
the two that every slice depends on removes that context tax without losing the trigger reach.
