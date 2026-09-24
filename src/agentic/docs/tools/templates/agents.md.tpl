---
layout: page
title: "Agents"
description: "Agent instruction files for the multi-agent orchestration system. Compatible with both opencode and claudecode."
nav_section: docs
---

DevBot ships agents across two modules: **primary agents** (invoked directly) and **subagents** (delegated to by a primary agent).

## Primary agents

Start here. Pick the experience that fits your workflow.

<!-- GENERATED:AGENTS_PRIMARY -->

## Subagents

Primary agents delegate to these.

<!-- GENERATED:AGENTS_SUBAGENTS -->

## Structure

The directory layout behind the tables above:

<!-- GENERATED:AGENT_TREE -->

## Shell strategy

Every agent that can run a shell command loads the shared `devbot:shell-strategy` skill, so the bash-vs-PTY decision lives in one place instead of being restated per agent:

- **bash tool** — quick, deterministic, non-interactive commands.
- **PTY session** (`pty_spawn`/`pty_write`/`pty_read`/`pty_kill`) — commands that may outlive the bash timeout (test suites, builds, migrations), prompt for input, or need their output watched while they run. The distinction is time, not command length.

The skill also carries the PTY output and stdin rules and the gotchas a PTY hides (a commit run in a PTY skips the post-commit hooks; PTY sessions do not inherit `DEV_BOT_SESSION_ID`).

`architect`, `critic`, and `po` deny the bash tool and also deny the whole PTY tool family — the PTY tools are plugin tools that never consult the runtime permission prompt, so a bash-only deny would have left them a shell.
