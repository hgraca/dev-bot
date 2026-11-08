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
devbot tool project-for-path <project> --key modules   # absence => enabled
devbot tool project-for-path <project> --key mcps      # {"atlassian": "enabled"}
```

`modules` reports the module gate, merged project-over-global with absence
meaning enabled. `mcps` reports the live per-server state from the generated
harness config. When the module is enabled but `atlassian` is `disabled` or
absent from `mcps`, ask the user whether to enable the MCP before continuing.

On yes, set `mcp.atlassian.enabled` to `true` in the generated harness config
and say the harness must be restarted — MCP tools load at start, so this session
stays without Jira. Never edit the config silently.

Module enabled **and** MCP enabled is the only state in which the steps below
run. In every other state skip the Jira work for the session and say so once.

## 1. Resolve the ticket — before refinement

The scout's report either names a matching ticket or says there is none. Ask the
user in one round:

- a ticket was reported → **confirm it** as `PROJ-123 — summary — URL`;
- the user has one → take the key they give;
- otherwise → offer to create one with `devbot:create-jira-issue`, which asks for
  the project, the epic and — for an epic — the `Stream` value.

The ticket must sit in **TODO or the equivalent first actionable status** —
never in the backlog, never in progress. Read its current status and, when it is
a backlog status, move it with the transitions the server lists.

Keep the resolved key in the conversation and reuse it in every later step.
Never create a second ticket for the same assignment.

## 2. Open the ticket — after refinement, before implementation

Before the first code change:

- append what the refinement produced to the description — the existing text
  stays, new `Problems:` and `Solutions:` bullets are added;
- list the transitions, then move the ticket to **DOING / In Progress** or its
  equivalent.

Show the description delta and the transition, then act: the plan the user
approved already covers both.

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

A pull request left open is not finished work: the ticket stays DOING until the
merge lands and the user confirms the finish.

## Rules

- **Discover first, then act** — tool names and field ids belong to the server.
- **List transitions before moving** — never assume a status name exists.
- **Reads are free, writes are not** — propose and confirm anything the user has
  not already approved; never act on a guessed issue.
- **One ticket** — never bulk-edit, never touch an issue outside the assignment.
- **Search before creating** — a duplicate is worse than a missing link.
- **No credentials** — the session's OAuth is the only auth; never hunt for a
  token.
