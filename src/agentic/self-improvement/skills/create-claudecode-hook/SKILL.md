---
name: create-claudecode-hook
description: "Use this skill whenever someone asks about Claude Code hooks or any Claude Code lifecycle automation — how to auto-format code, block tool calls, send notifications, inject context, auto-approve permissions, write hook scripts, configure PostToolUse/PreToolUse/Stop/Notification events, hook exit codes, or JSON output from hooks. Covers building, configuring, and using user-defined shell commands that run at lifecycle events."
---

# Building Claude Code Hooks

Hooks are user-defined shell commands that execute automatically at specific points in Claude Code's lifecycle. They give you **deterministic** control — certain actions always happen, not just when Claude decides to run them.

## Core Concepts

Every hook has three parts:

| Part        | What it is                     | Example                                            |
| ----------- | ------------------------------ | -------------------------------------------------- |
| **Event**   | When the hook fires            | `PostToolUse`, `PreToolUse`, `Stop`                |
| **Matcher** | Optional regex to narrow scope | `Edit\|Write`, `Bash`, `mcp__.*`                   |
| **Action**  | What runs                      | `type: "command"`, `"http"`, `"prompt"`, `"agent"` |

---

## Quick Setup

Hooks live inside the `hooks` key of a settings file:

```json
{
    "hooks": {
        "PostToolUse": [
            {
                "matcher": "Edit|Write",
                "hooks": [
                    {
                        "type": "command",
                        "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write"
                    }
                ]
            }
        ]
    }
}
```

### Where to put your settings file

| File                          | Scope             | Shareable?           |
| ----------------------------- | ----------------- | -------------------- |
| `~/.claude/settings.json`     | All your projects | No                   |
| `.claude/settings.json`       | This project      | Yes — commit to repo |
| `.claude/settings.local.json` | This project      | No — gitignored      |

After editing, Claude Code picks up changes automatically. Run `/hooks` inside Claude Code to browse all configured hooks by event.

---

## All Hook Events

For full input schemas and decision formats, see [references/events.md](references/events.md).

| Event                 | When it fires                                 | Blockable?                            |
| --------------------- | --------------------------------------------- | ------------------------------------- |
| `SessionStart`        | Session begins or resumes                     | No — stdout added to context          |
| `Setup`               | `--init-only` or `--init` in headless mode    | No                                    |
| `UserPromptSubmit`    | User submits a prompt, before Claude sees it  | Yes (exit 2)                          |
| `UserPromptExpansion` | A `/command` expands into a prompt            | Yes (exit 2)                          |
| `PreToolUse`          | Before a tool call executes                   | Yes (exit 2 or JSON)                  |
| `PermissionRequest`   | A permission dialog is about to appear        | Via JSON only                         |
| `PermissionDenied`    | Tool denied by auto-mode classifier           | No — return `{"retry":true}` to retry |
| `PostToolUse`         | After a tool call succeeds                    | Via JSON `decision: "block"`          |
| `PostToolUseFailure`  | After a tool call fails                       | No                                    |
| `PostToolBatch`       | After a full batch of parallel tool calls     | Via JSON                              |
| `Notification`        | Claude Code sends a notification              | No                                    |
| `MessageDisplay`      | Assistant message text is being displayed     | No                                    |
| `SubagentStart`       | A subagent is spawned                         | No                                    |
| `SubagentStop`        | A subagent finishes                           | No                                    |
| `TaskCreated`         | Task created via TaskCreate                   | Via JSON                              |
| `TaskCompleted`       | Task marked complete                          | Via JSON                              |
| `Stop`                | Claude finishes responding                    | Via JSON `decision: "block"`          |
| `StopFailure`         | Turn ends due to an API error                 | No                                    |
| `TeammateIdle`        | Agent team teammate about to go idle          | No                                    |
| `InstructionsLoaded`  | CLAUDE.md or `.claude/rules/*.md` file loaded | No                                    |
| `ConfigChange`        | A config file changes mid-session             | Yes (exit 2 or JSON)                  |
| `CwdChanged`          | Working directory changes (e.g. `cd` command) | No                                    |
| `FileChanged`         | A watched file changes on disk                | No — matcher = filenames to watch     |
| `WorktreeCreate`      | Worktree being created                        | Replaces default git behavior         |
| `WorktreeRemove`      | Worktree being removed                        | No                                    |
| `PreCompact`          | Before context compaction                     | No                                    |
| `PostCompact`         | After context compaction                      | No                                    |
| `Elicitation`         | MCP server requests user input                | Via JSON                              |
| `ElicitationResult`   | User responds to an MCP elicitation           | Via JSON                              |
| `SessionEnd`          | Session terminates                            | No                                    |

---

## Exit Codes

How your script communicates back to Claude Code:

| Code          | Meaning                                                                                                                                           |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `0`           | No decision — the normal permission flow continues. For `UserPromptSubmit` / `SessionStart`, anything on stdout is injected into Claude's context |
| `2`           | **Block** the action. Write the reason to stderr — Claude receives it as feedback and can adjust                                                  |
| Anything else | Action proceeds, but a hook error notice appears in the transcript                                                                                |

> Don't mix exit 2 with JSON stdout — Claude Code ignores JSON output when you exit 2.

---

## Recipes

### Desktop notification when Claude needs input

```json
{
    "hooks": {
        "Notification": [
            {
                "matcher": "",
                "hooks": [
                    {
                        "type": "command",
                        "command": "osascript -e 'display notification \"Claude needs attention\" with title \"Claude Code\"'"
                    }
                ]
            }
        ]
    }
}
```

Linux: use `notify-send 'Claude Code' 'Needs attention'`  
Windows: use `powershell.exe -Command "[System.Windows.Forms.MessageBox]::Show('Claude needs attention')"`

The `matcher` for `Notification` can be: `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, `elicitation_complete`, `elicitation_response`. Leave empty to catch all.

---

### Auto-format files after every edit

```json
{
    "hooks": {
        "PostToolUse": [
            {
                "matcher": "Edit|Write",
                "hooks": [
                    {
                        "type": "command",
                        "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write"
                    }
                ]
            }
        ]
    }
}
```

Hook input arrives as JSON on stdin. Use `jq` to extract fields (`brew install jq` / `apt-get install jq`).

---

### Block edits to protected files

Create `.claude/hooks/protect-files.sh`:

```bash
#!/bin/bash
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

PROTECTED=(".env" "package-lock.json" ".git/")

for pattern in "${PROTECTED[@]}"; do
  if [[ "$FILE_PATH" == *"$pattern"* ]]; then
    echo "Blocked: $FILE_PATH matches protected pattern '$pattern'" >&2
    exit 2
  fi
done

exit 0
```

```bash
chmod +x .claude/hooks/protect-files.sh
```

Register it:

```json
{
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "Edit|Write",
                "hooks": [
                    {
                        "type": "command",
                        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/protect-files.sh"
                    }
                ]
            }
        ]
    }
}
```

---

### Re-inject context after compaction

When Claude's context window fills up, compaction summarizes the conversation. Use `SessionStart` with `compact` to re-inject critical info:

```json
{
    "hooks": {
        "SessionStart": [
            {
                "matcher": "compact",
                "hooks": [
                    {
                        "type": "command",
                        "command": "echo 'Reminder: use Bun not npm. Run bun test before committing. Current sprint: auth refactor.'"
                    }
                ]
            }
        ]
    }
}
```

Stdout from `SessionStart` hooks is added to Claude's context.

---

### Auto-approve a specific permission prompt

```json
{
    "hooks": {
        "PermissionRequest": [
            {
                "matcher": "ExitPlanMode",
                "hooks": [
                    {
                        "type": "command",
                        "command": "echo '{\"hookSpecificOutput\": {\"hookEventName\": \"PermissionRequest\", \"decision\": {\"behavior\": \"allow\"}}}'"
                    }
                ]
            }
        ]
    }
}
```

Keep the matcher as narrow as possible — matching `.*` would auto-approve every prompt including file writes and shell commands.

---

### Prevent infinite Stop hook loops

Stop hooks fire every time Claude finishes. If your hook blocks, Claude keeps working — but after 8 consecutive blocks without progress, Claude Code overrides it. Guard against this:

```bash
#!/bin/bash
INPUT=$(cat)
if [ "$(echo "$INPUT" | jq -r '.stop_hook_active')" = "true" ]; then
  exit 0  # Already looping — let Claude stop
fi

# ... your actual check logic ...
```

---

## Combining Multiple Hooks

Multiple hooks on the same event run **in parallel**. Claude Code merges results after all finish — one hook returning `deny` doesn't stop others from executing.

For `PreToolUse` decisions, the most restrictive answer wins: `deny` > `ask` > `allow`. Text from `additionalContext` is concatenated from all hooks and passed to Claude together.

```json
{
    "hooks": {
        "PreToolUse": [
            {
                "matcher": "Bash",
                "hooks": [
                    {
                        "type": "command",
                        "command": "jq -r .tool_input.command >> ~/.claude/bash.log"
                    },
                    {
                        "type": "command",
                        "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/block-rm-rf.sh"
                    }
                ]
            }
        ]
    }
}
```

---

## Matcher Patterns by Event

| Event(s)                                                             | Matcher filters on         | Example values                                     |
| -------------------------------------------------------------------- | -------------------------- | -------------------------------------------------- |
| `PreToolUse`, `PostToolUse`, `PermissionRequest`, `PermissionDenied` | Tool name                  | `Bash`, `Edit\|Write`, `mcp__github__.*`           |
| `SessionStart`                                                       | How session started        | `startup`, `resume`, `clear`, `compact`            |
| `SessionEnd`                                                         | Why session ended          | `clear`, `resume`, `logout`, `other`               |
| `Notification`                                                       | Notification type          | `permission_prompt`, `idle_prompt`, `auth_success` |
| `SubagentStart` / `SubagentStop`                                     | Agent type                 | `general-purpose`, `Explore`, `Plan`               |
| `PreCompact` / `PostCompact`                                         | What triggered it          | `manual`, `auto`                                   |
| `FileChanged`                                                        | Literal filenames to watch | `.envrc\|.env`                                     |
| `ConfigChange`                                                       | Config source              | `user_settings`, `project_settings`, `skills`      |
| `StopFailure`                                                        | Error type                 | `rate_limit`, `server_error`, `auth_failed`        |
| `InstructionsLoaded`                                                 | Load reason                | `session_start`, `include`, `compact`              |
| `Setup`                                                              | CLI flag                   | `init`, `maintenance`                              |
| `UserPromptExpansion`                                                | Command name               | your skill/command names                           |
| `UserPromptSubmit`, `Stop`, `PostToolBatch`, etc.                    | No matcher support         | always fires                                       |

MCP tool names use the pattern `mcp__<server>__<tool>`, e.g. `mcp__github__search_repositories`.

---

## Hook Types Beyond Shell Commands

| Type        | Use when                                                           |
| ----------- | ------------------------------------------------------------------ |
| `"command"` | Local shell logic, file checks, formatting (most common)           |
| `"http"`    | POST event data to an external service or audit endpoint           |
| `"prompt"`  | You need judgment, not deterministic rules — uses Haiku by default |
| `"agent"`   | Verification needs to read files or run commands (experimental)    |

For full schemas on `http`, `prompt`, and `agent` types, see [references/hook-types.md](references/hook-types.md).

---

## Debugging

**Check registered hooks**: run `/hooks` inside Claude Code.

**View execution details**: start with `--debug-file`:

```bash
claude --debug-file /tmp/claude.log
# in another terminal:
tail -f /tmp/claude.log
```

Or run `/debug` mid-session.

**Test a script manually**:

```bash
echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' | ./my-hook.sh
echo $?
```

**Common issues**:

- Hook not firing → check matcher is case-sensitive and matches the exact tool name
- "command not found" → use absolute paths or `$CLAUDE_PROJECT_DIR`
- "jq not found" → `brew install jq` / `apt-get install jq`
- Script not running → `chmod +x ./my-hook.sh`
- JSON parse error → your shell profile may echo text on startup; wrap echo statements in `if [[ $- == *i* ]]; then ... fi`

---

## Reference Files

- [references/events.md](references/events.md) — detailed input schemas for every event
- [references/hook-types.md](references/hook-types.md) — full config for `http`, `prompt`, and `agent` hooks
- Official guide: https://docs.anthropic.com/en/docs/claude-code/hooks-guide
- Full reference: https://code.claude.com/docs/en/hooks
