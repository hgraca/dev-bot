# guards

Evaluates bash commands against configurable guard rules from global and project config files. Automatically blocks dangerous commands before they execute.

## OpenCode

Registered in `opencode.jsonc` as `tool.execute.before` plugin. Intercepts every bash/shell tool call and checks it against guard rules before execution.

No manual configuration needed.

### How it works

1. Agent invokes Bash tool call
2. `on-tool_execute_before-guards.ts` fires
3. Reads guard rules from global `.devbot.global.jsonc` and project `.devbot.project.jsonc`
4. If command matches guard rule, `throw` blocks execution with guard's message
5. If no guard matches, command proceeds normally

### Plugin path

`src/agentic/guards/hooks/opencode/on-tool_execute_before-guards.ts`

## Claude Code

Registered via `PreToolUse` hook. Fires before every `Bash` tool call and blocks commands that match guard rules.

### Prerequisites

- **bun** — install via `curl -fsSL https://bun.sh/install | bash`
- **jq** — install via `brew install jq` (macOS), `apt-get install jq` (Debian), or `dnf install jq` (Fedora)

### Registration

Add to `.claude/settings.local.json` (already gitignored):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash src/agentic/guards/hooks/claudecode/guards-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### How it works

1. Claude Code is about to execute Bash command
2. `PreToolUse` hook fires with matcher `Bash`
3. Hook script reads JSON event from stdin and extracts command
4. Runs `guards.ts` to evaluate command against guard rules
5. If command matches guard, outputs deny decision with reason
6. If no guard matches, allows command

### Hook script

Path: `src/agentic/guards/hooks/claudecode/guards-hook.sh`
