---
date: 2026-10-12
keywords: ["skill-description", "external-modules", "context-budget", "vendored-skill"]
---

# Vendored skills bypass the 400-byte description budget but still enter session context

`src/_shared/tests/skill-description-budget_tests.bats` enforces the 400-byte cap on first-party
`SKILL.md` frontmatter descriptions by scanning `src/agentic/**` only — an external module's skills,
symlinked from `vendor/`, are not scanned, so a fat vendored description ships unchallenged. That
description is still always-on context: once the declaring module is enabled, it is injected into
every session alongside the first-party ones. Example: Google's `modern-web-guidance` skill carries a
997-byte description (2.5× the budget). Nothing to fix — vendor content is read-only — but estimate a
module's per-session context cost with the vendored descriptions included, not just the first-party
set.
