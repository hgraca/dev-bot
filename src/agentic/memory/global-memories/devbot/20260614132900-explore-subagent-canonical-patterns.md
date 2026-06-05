---
date: 2026-06-14
keywords: ["devbot", "explore", "module", "canonical", "scaffold"]
---

## Use explore subagent to learn canonical structure before creating modules

Before creating a new dev-bot module, delegate to the explore subagent to examine 2-3 existing skill-only modules (e.g. architecture, explore, workflow). Ask it to return directory trees, functions.sh contents, install.sh/update.sh boilerplate, and SKILL.md frontmatter. This reveals the canonical module skeleton (functions.sh + install.sh + update.sh + skills/ + optional tests/) without guessing or reading dozens of files directly. The explore agent returns structured data the orchestrator can use directly as templates.
