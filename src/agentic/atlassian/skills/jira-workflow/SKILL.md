---
name: devbot:jira-workflow
description: "Use when the atlassian MCP is enabled and a dev session must resolve, open or close its Jira ticket — ticket lookup at session start, the DOING transition before implementation, the PR title prefix, and the DONE or CANCELED close at wrap-up. Triggers on 'jira ticket', 'close the ticket', 'move the ticket', 'PROJ-123'."
---

# Jira workflow — one ticket per assignment

The lifecycle contract between a dev session and its Jira ticket. The MCP
mechanics live in `devbot:atlassian` (auth, the discover-first rule, the read and
write paths) — that skill is the prerequisite, not a duplicate.

## Availability gate

Two independent switches must both be on:

```bash
devbot tool project-for-path <project> --key modules                    # absence => enabled
devbot tool project-for-path <project> --key mcps [--session-root DIR]  # server map
```

`modules` reports the module gate, merged project-over-global with absence
meaning enabled. `mcps` reports the generated harness config's per-server state
and `mcps_sources` names the files it read. In a monorepo session pass the
workspace root as `--session-root`: the live config belongs to the checkout the
harness runs in, not to the project that owns the file. When the module is
enabled but `atlassian` is `disabled` or absent from `mcps`, ask the user
whether to enable the MCP before continuing.

A configured `enabled` server is necessary, not sufficient: it can still be
offline or unauthenticated. If the first Jira call fails to connect or
authorise, say so and treat the ticket work as unavailable for this session —
`devbot:atlassian` carries the auth path.

On yes, apply the path the harness needs — `src/agentic/atlassian/docs.md` is
the source: opencode reads `mcp.atlassian.enabled` from the generated
`opencode.jsonc`, so set it to `true`; Claude Code has no per-server switch, so
set `enabled: true` in the module manifest and run `devbot reinit`. Either way
the harness must be restarted — MCP tools load at start, so this session stays
without Jira. Never edit a config silently.

Module enabled **and** MCP enabled is the only state in which the steps below
run. In every other state skip the Jira work for the session and say so once.

## 1. Resolve the ticket — before refinement

The scout's report either names a matching ticket or says there is none. Ask the
user in one round:

- a ticket was reported → **confirm it** as `PROJ-123 — summary — URL`;
- the user has one → take the key they give;
- otherwise → offer to create one with `devbot:create-jira-issue`, which asks for
  the project, the epic and — for an epic — the `Stream` value.

The ticket must end in **TODO or the equivalent first actionable status**. Read
its current status first: a ticket already in an actionable or in-progress
state is left alone — a resumed session keeps its DOING ticket DOING. Only a
backlog status is promoted, using the transitions the server lists, and nothing
is ever started here.

Keep the resolved key in the conversation and reuse it in every later step.
Never create a second ticket for the same assignment.

## 2. Open the ticket — after refinement, before implementation

Before the first code change:

- append what the refinement produced to the description — the existing text
  stays, new `Problems:` and `Solutions:` bullets are added;
- list the transitions, then move the ticket to **DOING / In Progress** or its
  equivalent.

Show the description delta and the transition, then act: the approved plan is
the explicit approval `devbot:atlassian` requires before a write. Anything
outside that plan goes back to the user first.

## 3. Pull request title

When a ticket is resolved, the PR title starts with its key:

```text
PROJ-1234: add ticket lookup to the scout report
```

Jira links the pull request to the issue from the key alone, so the prefix is
required, not cosmetic. `devbot:gh-create-pr` carries the title rules.

## 4. Close the ticket — at wrap-up

In the finish flow, once the user confirms the work is finished, move the ticket
to **DONE** or its equivalent — **CANCELED** when the work was abandoned. Ask
which when the outcome does not make it obvious. Add a closing comment only when
the description no longer explains the result.

Before DONE, confirm the work is actually delivered, judged by the workflow in
use:

- **worktrees** — the pull request is merged (`gh pr view <branch> --json
state,mergedAt`). An open pull request is not finished work: the ticket stays
  DOING, say so and leave it.
- **trunk** — the commit has landed on the default branch
  (`git log origin/<default> --oneline`), because trunk opens no pull request.

A later session that closes the ticket recovers the key from the pull request
title (the `PROJ-1234:` prefix Jira links) or by searching Jira for the issue —
never from the branch name alone, which is not required to carry it. When
neither finds it, ask the user.

## Rules

- **Discover first, then act** — tool names and field ids belong to the server.
- **List transitions before moving** — never assume a status name exists.
- **Reads are free, writes are not** — propose and confirm anything the user has
  not already approved; never act on a guessed issue.
- **One ticket** — never bulk-edit, never touch an issue outside the assignment.
- **Search before creating** — a duplicate is worse than a missing link.
- **No credentials** — the session's OAuth is the only auth; never hunt for a
  token.
