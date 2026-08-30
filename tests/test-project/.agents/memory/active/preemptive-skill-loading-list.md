---
tags: [bootstrap, session, skills]
description: Context skills that must be preemptively loaded for correct agent behavior
---

## Preemptive Context Skill Loading

The agent must preemptively load the following context skills at the start of every session:

- `devbot:software-development` — generic craft hub (code-quality, tests-first, commit protocol); carries the PHP rules annex for this PHP 8.4 / CQRS / message-bus kata.
- `devbot:explicit-architecture` — DDD + Hexagonal layering; needed for correct file placement in the port/adapter `src/` layout.
- `devbot:architecture-rules` — architecture priority order, security constraints, and forbidden patterns for this hexagonal codebase.
- `devbot:make-tests` — test strategy and conventions for the PHPUnit suite (unit/integration placement, naming).
- `test-driven-development` — tests written before implementation; the kata's refactoring work is TDD-shaped.
- `devbot:git-conventional-commits` — conventional commit message format (types, scope); needed before any commit.
- `devbot:git-atomic-commits` — one logical change per commit; keeps the refactoring history reviewable.
