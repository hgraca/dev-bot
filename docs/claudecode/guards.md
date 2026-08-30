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

### How it's wired

Declared in `src/agentic/guards/hooks.json` (`command.before`, `blocking: true`) and wired by the generic adapters — `on-hooks.ts` (OpenCode) and `on-hooks.py` (Claude Code).

## Claude Code

Registered via `PreToolUse` hook. Fires before every `Bash` tool call and blocks commands that match guard rules.

### Prerequisites

- **bun** — install via `curl -fsSL https://bun.sh/install | bash`
- **jq** — install via `brew install jq` (macOS), `apt-get install jq` (Debian), or `dnf install jq` (Fedora)

### Registration

Registration is handled by `src/harnesses/claudecode/hooks.json` (the generic dispatcher entry) — no per-module hook config needed.

### How it works

1. Claude Code is about to execute Bash command
2. `PreToolUse` hook fires with matcher `Bash`
3. Hook script reads JSON event from stdin and extracts command
4. Runs `guards.ts` to evaluate command against guard rules
5. If command matches guard, outputs deny decision with reason
6. If no guard matches, allows command

### How it's wired

Claude Code hooks are dispatched by `src/harnesses/claudecode/hooks/on-hooks.py` (the `pre-tool` phase reads the manifest and runs `guards.ts`).
