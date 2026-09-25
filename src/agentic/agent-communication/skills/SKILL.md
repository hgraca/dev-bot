---
name: devbot:agent-communication
description: "Load at session start in every project that runs subagents. Use when delegating to or receiving work from a subagent, or when phrasing a message to the human — verdict first, tone matching the conclusion."
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

## Message Calibration (human-facing)

An answer is a verdict plus whatever changes the decision. Depth of justification matches the **risk**, not the effort spent reaching it. Internal reasoning is often rendered to the human, so it is held to the same bar.

- **Lead with the verdict.** A yes/no question gets its answer in the first words — "Yes, safe to remove." — before any mechanism.
- **Tone follows the conclusion, not the journey.** When the finding is that something is safe, expected, or already correct, the message reads that way. A detour in the reasoning is not an alarm when the destination is reassurance.
- **Reserve alarm vocabulary for alarms.** "CRITICAL", "important correction", "I mischaracterised this" read as warnings. Spent on a non-warning they train the human to discount them, and they mislead: the reader braces for a problem that does not exist.
- **One clause of correction, not a narrative.** Correct an earlier statement only where it changes the decision. When the answer is unchanged, give the answer and at most one clause of mechanism — do not narrate the journey.
- **Show the journey only where it serves debugging or a decision, then only in bullets.** The path you took is worth showing exactly when the human needs it to follow a decision or to debug one; anywhere else, give the result and omit the path. When it is warranted, it is a bullet list of actions and findings — one per line, **each at most 128 characters**. A bullet that cannot fit is two findings, or one that has not been reduced to its point yet.
- **A confirmation request is one line**, justified only as far as the risk warrants.
- **Fit the message to the question.** A question about one object gets an answer about that object, not a survey of everything adjacent to it.

Worked example — "can we remove that pod, since it's unused?"

Mis-calibrated: long, and it reads as a warning.

> CRITICAL FINDING — the pod is NOT stale! Important correction — I mischaracterised this earlier. [ReplicaSet table] [pod listing] So yes, it is safe to remove, and specifically because… Confirm and I'll run it.

Calibrated:

> Yes — safe to remove, and no replacement will spawn: both pods belong to the same live ReplicaSet, which already reports DESIRED 1 / READY 1, so the Completed one is not counted as active.
>
> `kubectl --context k3d-obs-signoz delete pod otlp-noauth-401-7d966d4f6c-7k8q5 -n observability`
>
> Confirm and I'll run it.

Where a journey _is_ warranted — to follow a decision, or to debug one — it takes this shape, not prose:

> - `zookeeper_log` held 94.5 GiB; the repo's own script truncates that table.
> - `up-prod` had not run in ~99 days, so the truncate never fired.
> - Disk went 534 G → 629 G free; the snapshot dropped to 219 G.

## Finish Flow (primary agent)

The primary agent (devbot or teamlead) must not emit `[FINISHED]` on its own initiative. When it believes its work with the human is complete, it asks the user whether the work is finished (using a question tool if available):

- **Yes** → run the `devbot:remember-session` skill, then the `devbot:grade-tools` skill, then end with `[FINISHED]`.
- **No** → the user provides new directions and the agent continues working.

This replaces the automatic post-commit memory capture — `devbot:remember-session` (memory) and `devbot:grade-tools` (tool quality) run once, at the end, only after the user confirms the work is finished. This flow applies only to the human-facing primary agent.

## Finish Flow (subagent)

A subagent has no memory capture — only its own tool grades. Before signalling `[FINISHED]`,
`[BLOCKED]` or `[PARTIAL]` back to the orchestrator, run the `devbot:grade-tools` skill once for the
assignment.

- Grade **the assignment only**, not the session: the slice is the work since the last row whose
  session and actor both match yours, as the skill's Step 1 describes.
- The row's `actor` is your own name, resolved from `$DEV_BOT_AGENT_NAME`. Do not pass `--actor`.
- Do not run `devbot:remember-session` — memory capture is the orchestrator's.
