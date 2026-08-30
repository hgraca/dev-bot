---
date: 2026-08-21
keywords: ["skills", "devbot", "language-agnostic", "generification"]
see: ["ADRs/20260823111100-software-development-hub-skill-annexes.md"]
---

## Skills are principle-based and language-agnostic

> **SUPERSEDED** (2026-08-23) by `ADRs/20260823111100-software-development-hub-skill-annexes.md`: the "language's own skill directory" is now `software-development/annexes/php/` — plain reference `.md` files, not loadable skills.

Dev-bot skills state principles that apply to any language/technology; language-specific content is isolated. A skill's body is generified using a stable vocabulary (`composer.json` → "dependency manifest", `vendor/` → "vendored dependency tree", "PHP core globals" → "language stdlib symbols", `php-rules` → "language-specific rules", PSR-4 → "module-resolution conventions"), and content bound to one language is moved into a marked `## Language-specific checklists > ### <lang>` section (see `audit-security`, `review-implementation`) or folded into that language's own skill directory `dev/skills/php/`. Fully language-specific generators (e.g. `make-use-case`, which scaffolds `GetE\MessageBus\*` classes) are folded into the language-specific `message-bus` skill rather than kept as standalone generic-looking skills. Project-specific invocation commands (make targets, test runners) are deferred to each project's `project.md`, not hardcoded in a skill. Rationale: the toolkit must be reusable across arbitrary projects, not just the GET-E PHP app.
