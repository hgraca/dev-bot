---
name: agent-communication
description: "Structured inter-agent communication protocol with terminal status markers ([FINISHED], [BLOCKED], [NEEDS_INPUT], [PARTIAL]). Use this skill whenever you are about to delegate work to a subagent, or when you have been delegated a task as a subagent — before sending or responding to any inter-agent message."
---

# Agent Communication

Provides CLI tools for the structured inter-agent communication protocol. Validates that assistant messages end with canonical terminal status markers, reports message status, and inspects agent communication state (lock files, nudge counters).

## When to Use

| Situation                                                             | Tool                    |
| --------------------------------------------------------------------- | ----------------------- |
| Check if last assistant message has a valid status marker             | **agent-communication** |
| Debugging a stuck nudge cycle — check lock files or cooldown state    | **agent-communication** |
| Validate agent responses conform to the communication protocol        | **agent-communication** |
| Report current agent communication state (locks, counters, cooldowns) | **agent-communication** |
| Running a compliance check across messages                            | **agent-communication** |
| Any other task that does not involve agent communication status       | Nothing needed          |

**Run agent-communication to validate or inspect agent message status.** Keeps multi-agent sessions healthy by catching missing terminal markers early.

## How to Call

```
agent-communication command=<command> [options...]
```

| Parameter  | Required | Description                                                                                                                                  |
| ---------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `command`  | yes      | One of: `validate` — check last assistant message for terminal marker; `state` — print lock/cooldown/counter state; `check` — run all checks |
| `msg-file` | no       | Path to a JSON message file (for `validate` command). Reads from stdin if omitted.                                                           |

## Output Format

Reports results in structured text. The `validate` command prints the marker detection result. The `state` command prints lock file, cooldown, and counter information. Errors exit non-zero with a message.

## Post-Delegation Verification

After delegating to a subagent (critic, reviewer, tester, etc.), always verify the expected deliverable exists before accepting [FINISHED]

1. **Expected file**: `glob` for the file path that was in the delegation prompt
2. **If missing**: The subagent may have stalled — re-delegate with a shorter, more explicit prompt
3. **If present**: Read the file to verify content matches expectations

This prevents silent empty-task results where the subagent returns without producing the expected artifact.

Common patterns:

- Critic review → `glob` for `*review*` file
- Developer implementation → `glob` for expected source files
- Tester → `glob` for expected test files

## Pipe Mode

When `validate` is called with no `msg-file` argument, reads a JSON assistant message from stdin:

```
cat message.json | agent-communication command=validate
```

(Use pipe mode when checking a message inline, e.g. from a test or pipeline.)

## Examples

```
# Validate a message file
agent-communication command=validate msg-file="message.json"

# Check agent communication state
agent-communication command=state

# Run all checks
agent-communication command=check

# Pipe mode — validate message from stdin
echo '{"info":{"role":"assistant"},"parts":[{"type":"text","text":"All done.\\n[FINISHED]"}]}' | agent-communication command=validate
```

## Canonical Status Markers

Every assistant message must end with exactly one of these markers on its own line:

| Marker          | Meaning                                |
| --------------- | -------------------------------------- |
| `[FINISHED]`    | Work is genuinely complete             |
| `[BLOCKED]`     | Cannot proceed, external action needed |
| `[NEEDS_INPUT]` | Needs clarification from human         |
| `[PARTIAL]`     | Work is incomplete, must resume        |
