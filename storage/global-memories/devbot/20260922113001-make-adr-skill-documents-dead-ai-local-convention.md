---
date: 2026-09-22
keywords: ["devbot", "adr", "make-adr", "skill", "memory-vault"]
trigger-on: ["devbot-make-adr-skill"]
---

## `devbot:make-adr` documents a dead convention — write ADRs in the memory-vault format

The `devbot:make-adr` skill instructs the agent to save to `.ai/local/ADRs/ADR-{NNN}-{kebab-title}.md` and use its `In context of … we decided for …` template, with ADR numbers derived from the highest existing `ADR-NNN`. That directory no longer exists — `.ai/` is gone from the dev-bot/dev-tools repos — so a literal reading of the skill creates a stray directory and an ADR no vault search will ever find. The live convention is the memory vault: `.agents/memory/latent/ADRs/YYYYMMDDHHMMSS-<slug>.md`, YAML frontmatter of `date` + `keywords` (optionally `see`), and a body of one `##` declarative heading plus one or two prose paragraphs. Match the neighbouring files on disk, not the skill's template.
