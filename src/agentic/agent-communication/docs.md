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
work is done, blocked, or needs input. The canonical marker set — definitions and semantics — is
owned by the `devbot:agent-communication` skill; this page does not restate it.

One rule is checked mechanically. On `session.idle` the module's hook re-validates the last
assistant message with `--require-wait`: a `[WAITING_FOR_PTY]` whose message started no wait — no
completed `pty_spawn`, no `bash`/`shell` with `background: true` — fails with that reason. The flag
is opt-in because only a caller holding the message's tool parts can judge it; a text-only
invocation keeps marker-only semantics. The same pass names the marker the message actually ends on
(the one leading the last line), so a caller never has to re-derive it.

## Reporting to herdr

Inside a [herdr](/modules/tools/herdr) pane the same idle pass publishes that marker to the pane as
display-only metadata — the `devbot` token, e.g. `devbot=NEEDS_INPUT` — so the workspace manager can
show how a turn ended. It is metadata on purpose: a state report would take the pane's lifecycle
authority, rename its agent, and strand the pane as `unknown` on release. The token is cleared when
the turn does not _end_ on a marker — the validator still accepts one quoted mid-body, but only the
marker leading the last line is published — and it is left alone when the validator invocation
itself fails. The report is skipped entirely outside a herdr pane (`HERDR_ENV`/`HERDR_PANE_ID`) or
when herdr cannot be reached — a herdr failure never affects a turn. A subagent session never
publishes: it shares the pane, so its marker is not the pane's turn end.

## Protocol rules

- **Post-delegation verification** — the orchestrator checks that deliverables exist on disk before
  accepting `[FINISHED]`.
- **Prompt-opener gate** — file-producing agents must open with `Write <path> <verb>…` or block
  immediately.
- **First-tool-call invariant** — the first tool call must be the declared write; no reads before.
- **Stall ceiling** — the same subagent returning `[PARTIAL]` twice escalates to the human.

## How it is used

`devbot` (pair programmer) and `teamlead` (orchestrator) use agent-communication whenever they
delegate to a subagent, so handoffs are verified rather than assumed. The protocol is applied by the
agents that load this skill; the `agent-communication` tool validates a saved message against it on
demand.

## Configuration

No project configuration is required — the module is wired by installation alone.
