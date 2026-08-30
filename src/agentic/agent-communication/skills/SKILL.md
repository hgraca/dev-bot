---
name: devbot:agent-communication
description: "Structured inter-agent communication protocol with terminal status markers ([FINISHED], [BLOCKED], [NEEDS_INPUT], [PARTIAL]). Use this skill whenever you are about to delegate work to a subagent, or when you have been delegated a task as a subagent — before sending or responding to any inter-agent message."
---

# Agent Communication

Provides the `agent-communication` tool: validates that an assistant message ends with a canonical terminal status marker. Keeps multi-agent sessions healthy by catching missing terminal markers early.

## When to Use

| Situation                                                                  | Tool                    |
| -------------------------------------------------------------------------- | ----------------------- |
| Check whether an assistant message has a valid terminal status marker      | **agent-communication** |
| Validate that a subagent's response conforms to the communication protocol | **agent-communication** |
| Compliance check over a saved or piped assistant message                   | **agent-communication** |
| Any other task that does not involve agent communication status            | Nothing needed          |

## How to Call

```
agent-communication --msg-file <path>
```

| Parameter    | Required | Description                                                                                         |
| ------------ | -------- | --------------------------------------------------------------------------------------------------- |
| `--msg-file` | yes      | Path to a JSON message file to validate. Pass `-` (or `/dev/stdin`) to read the message from stdin. |
| `validate`   | no       | Optional subcommand — accepted and ignored (the tool only validates).                               |
| `mcp-meta`   | no       | Print the tool's MCP metadata (JSON) and exit — used for tool discovery.                            |

## Output Format

The tool prints `[agent-communication] OK — terminal marker found` on success (including non-assistant or empty messages, which have nothing to validate) and `[agent-communication] Missing terminal marker. Last line: "…"` on failure. Exit codes: `0` marker found (or nothing to validate), `1` marker missing, `2` file-not-found / parse error / missing `jq`.

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

Pass `-` as `--msg-file` to read a JSON assistant message from stdin:

```
cat message.json | agent-communication --msg-file -
```

(Use pipe mode when checking a message inline, e.g. from a test or pipeline.)

## Examples

```
# Validate a message file
agent-communication --msg-file message.json

# Validate a message from stdin
echo '{"info":{"role":"assistant"},"parts":[{"type":"text","text":"All done.\\n[FINISHED]"}]}' | agent-communication --msg-file -

# Self-description (MCP metadata)
agent-communication mcp-meta
```

## Canonical Status Markers

Every assistant message must end with exactly one of these markers on its own line:

| Marker          | Meaning                                |
| --------------- | -------------------------------------- |
| `[FINISHED]`    | Work is genuinely complete             |
| `[BLOCKED]`     | Cannot proceed, external action needed |
| `[NEEDS_INPUT]` | Needs clarification from human         |
| `[PARTIAL]`     | Work is incomplete, must resume        |

## Finish Flow (primary agent)

The primary agent (devbot or teamlead) must not emit `[FINISHED]` on its own initiative. When it believes its work with the human is complete, it asks the user whether the work is finished (using a question tool if available):

- **Yes** → run the `devbot:remember-session` skill, then end with `[FINISHED]`.
- **No** → the user provides new directions and the agent continues working.

This replaces the automatic post-commit memory capture — `devbot:remember-session` runs once, at the end, only after the user confirms the work is finished. Subagents signal `[FINISHED]` to the orchestrator as normal; this flow applies only to the human-facing primary agent.
