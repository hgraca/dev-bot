---
name: devbot:create-devbot-module
description: "Use this skill whenever the user asks to create a new DevBot module, add a module to dev-bot, scaffold a new agentic capability, or bootstrap a module with skills, hooks, tools, or commands — even if they do not say 'module'. Triggers on 'create module', 'new devbot module', 'scaffold module', 'add agentic module', or when the user describes a capability that needs a dedicated module in src/agentic/."
---

# Skill: Create DevBot Module

Create a new agentic module under `src/agentic/`.
Gather requirements through an interactive questionnaire, implementing each answer immediately into the module anatomy.
The questionnaire proceeds in order — ask one question at a time, implement the answer, then move to the next.

## Module Anatomy

Every agentic module lives at `src/agentic/<name>/` and follows this structure (include only what the module needs):

```
<module>/
  agents/           Agent profiles (agents are optionally shipped inside modules)
  commands/         Repeatable instruction sets invocable via agent input
  skills/           Agent-readable skill instructions (SKILL.md per skill)
  hooks/            Event-driven hooks
    git/            Git hooks (post-commit, etc.)
  hooks.json        Declarative hook manifest (harness-agnostic)
  tools/            Executable tools
    opencode/       TS thin wrapper for opencode tool palette
    claudecode/     MCP server or hook script
  memory/           Bootstrap files symlinked into `.agents/memory/` (external modules)
  tests/            BATS test suite
  install.sh        Idempotent OS dependency installer
  update.sh         Dependency update script
  init.sh           Per-project initialization (optional)
  up.sh             Post-docker startup script (optional)
  pre.sh            Prerequisites check (optional)
  mcp.opencode.json MCP server definition for auto-registration (optional)
```

## Lifecycle Script Conventions

### install.sh

- Idempotent — can be run multiple times safely.
- Installs OS-level dependencies (packages, runtimes, binaries).
- Run automatically by `bin/install.sh` which loops over all modules.

### update.sh

- Updates OS-level dependencies to latest compatible versions.
- Run automatically by `bin/update.sh` which loops over all modules.

### pre.sh

- Checks module prerequisites (Python 3, API reachability, etc.).
- Run automatically by `bin/install.sh` and `bin/update.sh` — looped over all modules.
- Must be idempotent and non-destructive.
- Warnings (not errors) for optional dependencies.
- Sources `./functions.sh` for shared utilities.

### init.sh

- Per-project initialization (optional). Run by `bin/init.sh`.
- Example: graphify module's init.sh sets up initial knowledge graph state.

### up.sh

- Post-docker startup script (optional). Run after `docker compose up`.
- Use for: pulling models, waiting for dependent services, seeding data.

## Hooks

Hooks are declared in `hooks.json` (harness-agnostic) and wired by a single generic adapter per harness — never a per-harness hook file. See [Hooks](/hooks) for the manifest schema.

- **OpenCode** — the generic adapter `src/harnesses/opencode/hooks/on-hooks.ts` reads every manifest and maps the 6 semantic events to the plugin API.
- **Claude Code** — the dispatcher `src/harnesses/claudecode/hooks/on-hooks.py` handles 5 phases (`pre-tool`, `post-file`, `post-bash`, `stop`, `startup`).
- **Git hooks** — targets under `hooks/git/`, wired into `.git/hooks/`.

The business logic lives in `tools/`; a hook's `run` command references it via `{module}/tools/…`.

**Exception**: a hook whose side effect can't be expressed as "run a command" (e.g. injecting a prompt via the harness client, or a two-phase trigger flow) stays a hand-written hook in the harness module (`src/harnesses/<harness>/hooks/`) — see `devbot:auto-recover`.

## Harness adapter modules (annex)

This skill covers **agentic modules** (`src/agentic/`). A **harness module** (`src/harnesses/`) is a runtime adapter. Only read the annex `references/harness-adapter.md` when the task is to add a new agent harness or extend an existing adapter — it covers the harness module anatomy, the six-event adapter contract, the reference adapters, and the step-by-step. Skip it otherwise.

## Tools

When a tool is present, it must:

- Contain a bash script so the user can trigger it directly from the shell.
- Default output format: Markdown.
- Agent tools (TS/JS wrappers around the bash script) default to JSON to save tokens.
- `.ts` files are the authoritative source of truth — business logic lives there.
- `.sh` files are thin CLI wrappers that delegate to `.ts` via `bun run`. They never contain business logic.
- `.py` scripts are internal helpers called by `.ts` or `.sh` as subprocesses; never the primary entry point for agents.

### Tool placement

- `tools/opencode/` — TS thin wrapper for the opencode tool palette.
- `tools/claudecode/` — MCP server or Claude Code hook script.

## Testing

Tests use the **bats** framework (Bash Automated Testing System). Install via:

```
npm install -g bats bats-assert bats-support
```

`make test` auto-installs bats if missing. Reference implementation: `src/agentic/tree/tests/tree_tests.bats`.

Test fixtures go in `<module>/tests/fixtures/` and should be minimal — create what is needed for the test, clean up after.

## Questionnaire

Ask one question at a time. After the user answers a question, immediately implement the answer by creating the corresponding files and directories in the module anatomy. Then ask the next question.

### Q1: Module Name

Ask: **"What is the name of the new module?"**

If the project name in `.agents/devbot.jsonc` is `"dev-bot"`, the module is created at `src/agentic/<name>/`.

If the project name is NOT `"dev-bot"`, also ask: **"Under what file path should we create the new module?"**

**Implementation**: Create the module directory at the resolved path. Initialize it with a `functions.sh` file that sources the shared library:

```bash
#!/usr/bin/env bash
# src/agentic/<name>/functions.sh
# Thin wrapper: sources the root shared library.
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export MODULE_DIR
source "$MODULE_DIR/../../_shared/functions.sh"
```

### Q2: Prerequisites

Ask: **"What are the prerequisites for installing this module?"**

Examples: Node.js ≥18, Python 3.9+, Docker, a specific system package, an API key, network access to a service.

**Implementation**: Write `pre.sh` that checks these prerequisites. Use the shared functions from `functions.sh` (`_info`, `_ok`, `_warn`, `_error`). Check for binaries with `command -v`, versions with `--version`, API reachability with `curl --head`. Exit 0 on success, non-zero on hard failures. Warnings only for optional dependencies.

### Q3: Install Behavior

Ask: **"What should the behavior be when installing this module?"**

Describe what `install.sh` should do: which packages to install, which binaries to fetch, which config files to write, which symlinks to create.

**Implementation**: Write `install.sh`. Must be idempotent. Source `functions.sh` for utilities. Follow the pattern from existing modules (e.g., `src/agentic/tree/install.sh`).

### Q4: Update Behavior

Ask: **"What should the behavior be when updating this module?"**

Describe what `update.sh` should do: update packages to latest, re-fetch binaries, refresh config.

**Implementation**: Write `update.sh`. Often re-executes `install.sh` or performs version-specific upgrades. Source `functions.sh`.

### Q5: Up Behavior (devbot up)

Ask: **"What should the behavior be when starting devbot with `devbot up`?"**

Describe what `up.sh` should do when docker services come online: pull models, seed data, wait for dependencies, run migrations.

**Implementation**: Write `up.sh` (optional — only if behavior is described). Source `functions.sh`.

### Q6: Init Behavior

Ask: **"What should the behavior be when initializing a project with this module?"**

Describe what `init.sh` should do when a new project is set up: create initial state, register config, set up project-local resources.

**Implementation**: Write `init.sh` (optional — only if behavior is described). Source `functions.sh`.

### Q7: Hooks

Ask: **"Does the new module have a hook?"**

If yes, ask:

1. **"What event does the hook react to?"** — semantic events: `file.edited`, `command.before`, `command.after`, `session.idle`, `session.created`, `session.error`. Git events: `post-commit`, `post-checkout`, `pre-push`.

2. **"What does the hook do?"** — Describe the hook's behavior (this becomes a `tools/` entry).

3. **"Does it have another hook?"** — If yes, repeat questions 1-2.

**Implementation** for each hook:

- **Manifest hook** (the common case): write the logic in `tools/<tool>.{ts,sh}` and declare it in `hooks.json`:

    ```json
    {
        "hooks": [
            {
                "id": "my-hook",
                "event": "file.edited",
                "match": { "file": "\\.ext$" },
                "run": ["bash", "{module}/tools/my-tool.sh", "{file}"]
            }
        ]
    }
    ```

- **Git hook**: Create `hooks/git/<hook-name>`. Executable bash script or symlink target.

- **Harness-specific hook** (rare — side effects the manifest can't express): create the hook in `src/harnesses/<harness>/hooks/` (hand-written) and note it as an exception.

### Q8: Tools

Ask: **"Does the new module have tools?"**

If yes, ask:

1. **"What is the tool name?"** — Lowercase, hyphens. E.g., `devbot:search-code`, `devbot:format-md`.

2. **"What does the tool do?"** — Describe the tool's behavior, inputs, and outputs.

3. **"Does it have another tool?"** — If yes, repeat questions 1-2.

**Implementation** for each tool:

The tool directory goes at `tools/<tool-name>/` and must contain:

- `<tool-name>.ts` — **Source of truth.** All business logic. Exports the opencode tool. Also has a `main()` for CLI invocation. Accepts `--json` / `--markdown` flags.
- `<tool-name>.sh` — **Thin CLI wrapper.** Calls the `.ts` via `bun`. Never contains business logic.

Tool directory structure:

```
tools/
  <tool-name>/
    <tool-name>.ts    Source of truth — business logic + opencode tool export
    <tool-name>.sh    Thin CLI wrapper — delegates to .ts via bun
```

Additionally, create:

- `tools/opencode/` — if separate opencode-specific wrappers are needed (rare — usually the `.ts` directly exports the tool).
- `tools/claudecode/` — if a Claude Code MCP server or hook script is needed.

### MCP Tool Exposure via `mcp-meta`

Every tool `.sh` script **must** handle a `mcp-meta` subcommand. The `tools-mcp` MCP server runs `<tool>.sh mcp-meta` to discover tools and their metadata. Tools without this subcommand are not exposed.

When invoked with `mcp-meta` as the first argument, the script must print a JSON object to stdout and exit 0:

```json
{
    "name": "tool-name",
    "description": "What the tool does",
    "parameters": {
        "type": "object",
        "properties": {
            "args": {
                "type": "array",
                "items": { "type": "string" },
                "description": "CLI args: <positional> [--flags]"
            }
        },
        "required": ["args"]
    }
}
```

- `name` — becomes `devbot-tools_<name>` in the MCP palette
- `description` — shown to the LLM when deciding which tool to call
- `parameters` — must use a single `args` (string array). The LLM constructs the full CLI as an array of strings, and the server passes them to the script as positional arguments. This works regardless of the script's CLI convention (positional, flags, etc.)

For tools that take no arguments (e.g., fire-and-forget), use `"properties": {}` and omit `"required"`.

The `mcp-meta` case must be placed **before** any dependency checks or `exec` calls. Example:

```bash
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  mcp-meta)
    cat <<'JSON'
{"name":"format-json","description":"Format JSON/JSONC files via prettier","parameters":{"type":"object","properties":{"args":{"type":"array","items":{"type":"string"},"description":"File path(s) to format"}},"required":["args"]}}
JSON
    exit 0
    ;;
esac

# ...normal tool logic...
```

**Symlink-safe `SCRIPT_DIR`**: Tool scripts are called via symlinks in `.opencode/tools/`. If the script resolves its own directory (e.g., to find a companion `.py` file), use `readlink -f` to resolve through the symlink:

```bash
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# NOT: SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

### Q9: Skills

Ask: **"Do you want to create skills for this module?"**

If yes, use the `devbot:create-skill` skill to create each skill. Keep repeating until the user has no more skills to create.

**Implementation**: Skills go under `skills/<skill-name>/SKILL.md`. Each skill follows the canonical SKILL.md format with YAML frontmatter (name, description required). Use `devbot:create-skill` skill for each one.

### Q10: Commands

Ask: **"Do you want to create commands for this module?"**

If yes, ask:

1. **"What is the command name?"**
2. **"What does the command do?"**
3. **"Does it have another command?"** — If yes, repeat questions 1-2.

**Implementation**: Commands go under `commands/<command-name>.md`. Each command is a repeatable instruction set invocable via agent input. Format as markdown with clear procedure steps.

### Q11: Memory (Transient)

Ask: **"Do you want to add transient memories to the module?"**

Transient memories are wired into the project's `.agents/memory/` vault via symlinks but are not committed in the target repo. Only apply for **external modules**.

If yes, ask:

1. **"What bootstrap memories does the module add?"** — Files wired into `.agents/memory/active/`.
2. **"What ADRs does the module add?"** — Architecture Decision Records.
3. **"What PDRs does the module add?"** — Product Decision Records.
4. **"What project-specific memories does the module add?"**
5. **"What references does the module add?"**

**Implementation**: Memory files go under `memory/` in the module, organized by subfolder matching the vault structure (`active/`, `latent/ADRs/`, `latent/PDRs/`, `references/`). During wiring, they are symlinked into the project's `.agents/memory/` at the corresponding paths.

## Gate Check

Before signalling completion, verify:

| #   | Gate                                                                                                         | Pass/Fail |
| --- | ------------------------------------------------------------------------------------------------------------ | --------- |
| 1   | Module directory exists at correct path                                                                      |           |
| 2   | `functions.sh` present and sources `../../_shared/functions.sh`                                              |           |
| 3   | All lifecycle scripts (install.sh, etc.) source `functions.sh`                                               |           |
| 4   | `install.sh` is idempotent                                                                                   |           |
| 5   | `pre.sh` is non-destructive (warnings only for optional deps)                                                |           |
| 6   | Tools: `.ts` is source of truth; `.sh` handles `mcp-meta` subcommand with valid JSON                         |           |
| 7   | Skills: each has valid SKILL.md with YAML frontmatter                                                        |           |
| 8   | Hooks: declared in `hooks.json` manifest (logic in `tools/`); hand-written only for the documented exception |           |
| 9   | Commands: each has clear procedure in markdown                                                               |           |
| 10  | Tests directory created (even if empty — for future BATS tests)                                              |           |
| 11  | No file contains `no-vcs` references (except .gitignore)                                                     |           |
| 12  | Module does not shadow an existing module name                                                               |           |
| 13  | Tools: each `.sh` handles `mcp-meta` subcommand with valid JSON                                              |           |

## Completion

When all questions are answered and all components implemented:

- Report the module path, list all created files with line counts.
- Signal `[FINISHED]` with the module path and file manifest.
