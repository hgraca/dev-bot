# format-md

Aligns markdown table columns automatically.

## OpenCode

Registered in `opencode.jsonc` as `file.edited` event plugin. Fires whenever `.md` file is edited — runs `format-md.sh <path>` in background.

No manual configuration needed.

## Claude Code

Registered via `PostToolUse` hook. Fires after every `Edit|Write` tool call on `.md` file.

### Prerequisites

- **jq** — install via `brew install jq` (macOS), `apt-get install jq` (Debian), or `dnf install jq` (Fedora)

### Registration

Hook is registered in `.claude/settings.local.json` (already gitignored):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash src/agentic/format-md/hooks/claudecode/format-md-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### How it works

1. Claude Code edits or writes file
2. `PostToolUse` hook fires with `Edit|Write` matcher
3. Hook script reads JSON event from stdin and extracts `file_path`
4. If file ends with `.md`, it runs `format-md.sh` on it
5. Non-markdown files are silently skipped

### Hook script

Path: `src/agentic/format-md/hooks/claudecode/format-md-hook.sh`
