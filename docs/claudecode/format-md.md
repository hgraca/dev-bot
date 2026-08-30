# format-md

Aligns markdown table columns automatically.

## OpenCode

Registered in `opencode.jsonc` as `file.edited` event plugin. Fires whenever `.md` file is edited — runs `format-md.mcp.sh <path>` in background.

No manual configuration needed.

## Claude Code

Registered via `PostToolUse` hook. Fires after every `Edit|Write` tool call on `.md` file.

### Prerequisites

- **jq** — install via `brew install jq` (macOS), `apt-get install jq` (Debian), or `dnf install jq` (Fedora)

### Registration

Registration is handled by `src/harnesses/claudecode/hooks.json` (the generic dispatcher entry) — no per-module hook config needed.

### How it works

1. Claude Code edits or writes file
2. `PostToolUse` hook fires with `Edit|Write` matcher
3. Hook script reads JSON event from stdin and extracts `file_path`
4. If file ends with `.md`, it runs `format-md.mcp.sh` on it
5. Non-markdown files are silently skipped

### How it's wired

Claude Code hooks are dispatched by `src/harnesses/claudecode/hooks/on-hooks.py` (the `post-file` phase reads the `format-md` manifest and runs `format-md.py`).
