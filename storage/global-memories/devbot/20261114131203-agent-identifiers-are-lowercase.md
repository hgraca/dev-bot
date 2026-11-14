---
date: 2026-11-14
keywords: ["devbot", "agent-name", "subagent-type", "opencode", "claudecode"]
aliases: ["agent identifier", "lowercase agent name", "subagent_type mismatch"]
trigger-on: ["devbot-delegate-reviewer", "devbot-agent-rename"]
supersedes: ["devbot/20261029110000-subagent-type-name-is-case-sensitive.md"]
---

## Agent identifiers are lowercase: `name:` must match the filename

An agent's identity is three surfaces that must agree: the file name (`scout.md`), the frontmatter `name:` value, and every `@handle` in prose. dev-bot registers them lowercase — `name: scout` in `scout.md` — and the harness resolves `subagent_type` case-sensitively, so `task(subagent_type: "scout")` is the correct call and any CamelCase spelling is an `Unknown agent type` mismatch. The registry exposed both spellings before the migration (it listed `architect` and `Architect` as separate rows), which is why a wrong lookup could look like a working one; `devbot list agents` now shows one row per agent. Keep `description:` fields, job titles ("Security Engineer", "Software Architect", "Product Owner") and the product brand "DevBot" capitalised — only identifiers and references to the agent go lowercase — and treat a capitalised `@[A-Z]` handle as the regression signal. `src/agentic/devteam/tests/agent_names_tests.bats` guards the invariant, including that every `agent` override key names a declared agent.
