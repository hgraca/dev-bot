---
layout: page
title: Agent Communication
description: Structured inter-agent protocol for reliable delegation.
nav_section: docs
---

A structured protocol that lets agents delegate work to each other with clear handoff, status tracking, and delivery verification.

## Terminal Status Markers

Every agent message ends with exactly one marker:

| Marker          | Meaning                                         |
| --------------- | ----------------------------------------------- |
| `[FINISHED]`    | Work genuinely complete                         |
| `[BLOCKED]`     | Cannot proceed, external action needed          |
| `[NEEDS_INPUT]` | Needs clarification from human or another agent |
| `[PARTIAL]`     | Work incomplete, must resume                    |

## Protocol Rules

- **Post-delegation verification**: orchestrator checks that deliverables exist on disk before accepting `[FINISHED]`
- **Prompt-opener gate**: file-producing agents must open with `Write <path> <verb>...` or block immediately
- **First-tool-call invariant**: first tool call must be the declared write — no reads before
- **Stall ceiling**: same subagent returning `[PARTIAL]` twice → escalate to human

## How agents use it

The `devteam` (TeamLead orchestrator) and `devbot` (pair programmer) use agent-communication when delegating to subagents. The protocol ensures reliable handoffs with verified deliverables.

## See also

- [Agents](/agents) — agent roster and descriptions
- [DevTeam Workflow](/module-reference) — planning and implementation cycles
