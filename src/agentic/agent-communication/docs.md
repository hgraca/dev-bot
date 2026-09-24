---
title: Agent Communication
description: Structured inter-agent protocol for reliable delegation.
skills: ["devbot:agent-communication"]
tools:
  agent-communication: Validates a saved message against the protocol
---

A structured protocol that lets agents delegate work to each other with clear handoff, status
tracking, and delivery verification.

## What it does

Every agent message ends with exactly one terminal marker, so a caller always knows whether the
work is done, blocked, or needs input:

| Marker          | Meaning                                         |
| --------------- | ----------------------------------------------- |
| `[FINISHED]`    | Work genuinely complete                         |
| `[BLOCKED]`     | Cannot proceed, external action needed          |
| `[NEEDS_INPUT]` | Needs clarification from human or another agent |
| `[PARTIAL]`     | Work incomplete, must resume                    |

## Protocol rules

- **Post-delegation verification** — the orchestrator checks that deliverables exist on disk before
  accepting `[FINISHED]`.
- **Prompt-opener gate** — file-producing agents must open with `Write <path> <verb>…` or block
  immediately.
- **First-tool-call invariant** — the first tool call must be the declared write; no reads before.
- **Stall ceiling** — the same subagent returning `[PARTIAL]` twice escalates to the human.

## How it is used

`devbot` (pair programmer) and `teamlead` (orchestrator) use agent-communication whenever they
delegate to a subagent, so handoffs are verified rather than assumed. The round-trip is checked by
a harness hook on session idle, so the protocol applies whether or not the agent is thinking about
it.

## Configuration

No project configuration is required — the module is wired by installation alone.
