---
name: devbot:create-jira-issue
description: "Use when creating a Jira work item — decide between epic, story, task and subtask, write a Problems/Solutions description, and place it in the right project, epic and Stream. Triggers on 'create a jira issue', 'create a ticket', 'open a story', 'new epic', 'subtask'."
---

# Create a Jira issue

Drive Jira through the Rovo MCP — `devbot:atlassian` carries auth and the
discover-first rule. This skill decides **what** the item is and **how** it is
written; the MCP calls are only the mechanics.

## 1. Classify the item

| Type        | Use when                                                            | Example                                   |
| ----------- | ------------------------------------------------------------------- | ----------------------------------------- |
| **Epic**    | Work spanning releases, broken into several stories or tasks        | "Ticket integration across the lifecycle" |
| **Story**   | The user can see the change — a feature or behaviour they asked for | "Scout reports the matching Jira ticket"  |
| **Task**    | Purely technical; the user may never notice it                      | "Report live MCP state from a tool"       |
| **Subtask** | A slice of one story or task that deserves its own tracking         | "Add the `--key mcps` branch"             |

A story describes an outcome, a task describes a change. When both readings fit,
pick the story — the user-visible framing survives reprioritisation better.

## 2. Summary

The same rules as a commit subject (`devbot:git-commits`): imperative, lowercase
start, no trailing period, at most 72 characters. It names the change, not the
files.

## 3. Description — the why, not the how

The same two lists a commit body carries:

```text
Problems:
- <what is wrong, missing, or at risk — ≤72 chars>
- <what is wrong, missing, or at risk — ≤72 chars>

Solutions:
- <what this does about it — ≤72 chars>
- <what this does about it — ≤72 chars>
```

One bullet per distinct problem and solution, each within 72 characters. The
description carries the problem and the intent; the implementation plan and the
file list belong to the code, not the ticket.

## 4. Placement

Ask in one round, then act:

- **Project** — which Jira project; list the visible ones when it is not obvious.
- **Epic** — the parent epic for a story or task; nothing for an epic.
- **Stream** — the custom property `Stream`, **epics only**. Read the field
  metadata for its id and allowed values, then ask which value applies — never
  guess a value or a field id.
- **Parent** — the story or task a subtask belongs to.

## 5. Create, then set the status

Present the complete issue — project, type, summary, description, parent and
`Stream` — and wait for one explicit go. On approval:

1. create the issue;
2. read its status — when it landed in Backlog or another non-actionable status,
   list the transitions and move it to **TODO / To Do** or the equivalent;
3. never leave it in Backlog, and never start it.

## 6. Report

```text
PROJ-123 — <summary> — https://<site>.atlassian.net/browse/PROJ-123
```

State the issue type and its parent so a misplacement is visible immediately.
