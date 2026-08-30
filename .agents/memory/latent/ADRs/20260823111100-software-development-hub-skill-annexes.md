---
date: 2026-08-23
keywords: ["skills", "devbot", "software-development", "annex", "agent-profiles"]
see: ["ADRs/20260821174500-skills-principle-based-language-agnostic.md"]
---

## Generic software-development craft lives in a hub skill; PHP skills are annexes

Generic software-development craft — code-quality principles (optimal-over-easy, simplicity-first, no-silent-assumptions, surgical-changes, small-fix-perfectionism), the tests-first discipline, the commit protocol, and cross-cutting rules (migrations-in-atomic-commit, CLI `WARN:`/`ERROR:`/`FATAL:` prefixes, `py_compile`, surface-pre-existing-issues) — is consolidated into one hub skill at `src/agentic/dev/skills/software-development/SKILL.md`. The four PHP skills (`php-rules`, `laravel`, `message-bus`, `phpunit`) are reframed as **annexes** of that hub: they carry a `## Annex of \`software-development\`` header and a pointer back, and are loaded only when the agent works with PHP (or the corresponding technology). Agent profiles (`devbot.md`, `developer.md`) no longer carry that craft inline — they "enforce loading" the hub skill at session start instead, keeping the profile lean and role-specific. Rationale: a single source of truth for craft rules means they are edited once and inherited everywhere; the profile stays focused on identity/lifecycle; language-specific content stays isolated in annexes, consistent with the earlier language-agnostic-skills decision.
