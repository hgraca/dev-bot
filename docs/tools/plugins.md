---
layout: page
title: Plugins
description: OpenCode lifecycle hooks that fire automatically.
nav_section: docs
---

Plugins are OpenCode extensions written in TypeScript. They fire on specific lifecycle events to inject context, enforce rules, or capture knowledge — without the agent needing to invoke them.

## Plugin Events

| Event                 | When it fires           | Example plugins                                 |
| --------------------- | ----------------------- | ----------------------------------------------- |
| `session.created`     | New session starts      | graphify update                                 |
| `session.error`       | Provider error occurs   | auto-recover                                    |
| `session.idle`        | Session goes idle       | agent communication (status-marker validation)  |
| `tool.execute.before` | Before any bash command | guards                                          |
| `tool.execute.after`  | After a tool runs       | remember-session, graphify update (post-commit) |
| `file.edited`         | Any file is saved       | format-md/json/yml, k8s lint, memory reindex    |

## Included Plugins

| Plugin                  | What it does                                                  |
| ----------------------- | ------------------------------------------------------------- |
| **guards**              | Blocks dangerous bash commands before execution               |
| **auto-recover**        | Detects transient errors and injects silent recovery prompts  |
| **format-md**           | Auto-formats markdown files on save                           |
| **format-json**         | Auto-formats JSON/JSONC files on save                         |
| **format-yml**          | Auto-formats YAML files on save                               |
| **remember-session**    | Promotes learnings to memory after commits                    |
| **graphify-update**     | Re-indexes knowledge graph on session start and after commits |
| **memory-reindex**      | Re-indexes QMD memory on file changes                         |
| **agent-communication** | Validates status markers when the session goes idle           |
| **k8s-lint**            | Lints Kubernetes manifests on save                            |

## How it works

Plugin `.ts` files live in `src/agentic/<module>/hooks/opencode/`. During install, they're symlinked into `.opencode/plugins/devbot/` and auto-discovered by OpenCode.

## See also

- [Guards](/tools/guards) — command safety rules
- [Module Reference](/module-reference) — plugin anatomy and lifecycle
