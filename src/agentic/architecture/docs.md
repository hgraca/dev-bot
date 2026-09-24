---
title: "Architecture"
description: "Architecture governance — design rules, layered architecture, ADRs, and codebase audits."
skills: ["architecture-rules", "audit-codebase", "audit-testsuite", "explicit-architecture", "make-adr"]
---

Keeps an agent honest about the shape of a codebase — what the layers are, where a file belongs, and what a change is allowed to touch.

## What it does

- **`architecture-rules`** — the project's design direction and security constraints, read before an architectural decision or a code-quality review.
- **`explicit-architecture`** — layer dependencies and file placement in a layered codebase.
- **`make-adr`** — records an architecture decision as an ADR.
- **`audit-codebase`** — audits for pattern drift, inconsistencies and architectural erosion.
- **`audit-testsuite`** — documents a test-suite run: results, bugs found, coverage.

## Configuration

The rules themselves live in the project's memory vault (`.agents/memory/`). No module configuration is required.

## See also

- [Memory](/modules/agentic/memory) — where ADRs and architecture rules are stored
- [Create a module](/create-a-module) — module anatomy
