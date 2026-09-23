---
date: 2026-09-23
keywords: ["codebase-index", "codebase-memory", "skill-name", "codebase_index_provider"]
---

# `devbot:codebase-index` is a deliberate shared slot name, not a duplicate

`src/agentic/codebase-index/skills/SKILL.md` and `src/agentic/codebase-memory/skills/SKILL.md` both declare `name: devbot:codebase-index`. This is **by design**: the two modules are mutually exclusive engines for one toolkit slot, selected by the global-only key `codebase_index_provider` (`src/_shared/functions.sh` `_devbot_get_disabled_modules`, which auto-appends the non-selected engine to the disabled set — see also `docs/configuration.md` §`codebase_index_provider`). Exactly one is ever wired, so exactly one skill answers to the name, and every reference to `devbot:codebase-index` resolves to whichever engine is active.

A reviewer auditing a changeset that touches either skill will flag the duplicate as a name collision that "shadows a skill". **Do not rename it** — renaming breaks the provider swap, because agents and docs reference the slot name, not the engine. A name-uniqueness test over `src/agentic/**/skills/**/SKILL.md` would produce a false failure here. The confusion is now pre-empted by a "Shared slot" note in both skill bodies; the same convention exists elsewhere (qmd/ollama engine swaps) — check for a selector key before treating a repeated skill name as a bug.
