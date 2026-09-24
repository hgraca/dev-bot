---
title: "Explore"
description: "Codebase exploration — session context gathering, project reports, and code search."
commands: ["create-project-report", "gather-context"]
skills: ["create-project-report", "gather-context", "search-code"]
---

Finding your way around a codebase you have not seen before — the module behind the context a session starts with.

## What it does

- **`gather-context`** (skill and command) — primes a session from a few keywords: memory search, git state, the knowledge graph, and the directory structure, into a report the primary agent reads.
- **`create-project-report`** — writes `.agents/memory/active/project.md`, the project's own description, used when it is missing or stale.
- **`search-code`** — locates a definition and follows the architecture around it.

## Configuration

No project configuration is required.

## See also

- [Memory](/modules/agentic/memory) — where the project report is stored
- [Git](/modules/agentic/git) — the git-report tool `gather-context` calls
