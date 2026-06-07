---
tags: [bootstrap, project]
description: dev-bot — agentic dev toolkit for GET-E, multi-agent orchestration on OpenCode
---

## What this project is

dev-bot is an agentic software development toolkit for the GET-E engineering team. Provides multi-agent system (DevBot orchestrator + 8 specialized subagents) running on OpenCode (or Claude Code). Written in Bash, TypeScript, Python, and Markdown. Handles planning, implementation, testing, review, architecture, security, and memory for AI-assisted development workflows.

## Sibling projects

You can get the list of sibling projects from .devbot.global.jsonc::projects

## Repository layout

| Path            | Contents                                                                                                                                                                                                                                                                       |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `.opencode/`    | OpenCode runtime: agents (9), skills (20 modules, symlinked from `src/`), commands (6), tools (11), plugins (8)                                                                                                                                                                |
| `src/`          | Module source — each has skill, hooks, tools, tests, lifecycle scripts                                                                                                                                                                                                         |
| `src/_shared/`  | Shared library: `functions.sh` (15+ utility functions), `read_jsonc.py` (JSONC parser)                                                                                                                                                                                         |
| `src/agentic/`  | Agent definitions (9 agents: devbot, po, architect, critic, developer, reviewer, tester, scout, security)                                                                                                                                                                      |
| `src/agentic/`  | 23 modules: agent-communication, architecture, auto-recover, codebase-index, chrome-devtools, context7, dev, docs, explore, external-modules, format-md, git-report, graphify, guards, memory, playwright, qmd, repomix, security, self-improvement, tree, websearch, workflow |
| `src/tools/`    | 3 tools: ollama, litellm, opencode — each with `install.sh`, `init.sh`, `update.sh`; ollama + litellm also have `docker-compose.yml`                                                                                                                                           |
| `bin/`          | CLI entry (`devbot`) + lifecycle scripts (install, init, update, up, down)                                                                                                                                                                                                     |
| `docs/`         | Module docs, agent docs, config ref, claudecode/ and opencode/ subfolders                                                                                                                                                                                                      |
| `.ai/devbot/`   | Agent memory vault (gitignored): bootstrap, latent notes, work folders                                                                                                                                                                                                         |
| `no-vcs/`       | Runtime symlinks (agents, skills, commands from vendor), node_modules, index (gitignored per `ignore.md`)                                                                                                                                                                      |
| `graphify-out/` | Knowledge graph output dir (gitignored)                                                                                                                                                                                                                                        |

## Architecture

Modular monolith + symlink-based plugin wiring. Each module under `src/agentic/<name>/` follows consistent layout:

| Component                      | Description                                                      |
| ------------------------------ | ---------------------------------------------------------------- |
| `skills/<skill-name>/SKILL.md` | Agent-readable skill instructions                                |
| `tools/`                       | Executable tools (Bash, Python, TS) wired into OpenCode          |
| `hooks/`                       | Lifecycle hooks (opencode/ and claudecode/ variants)             |
| `tests/`                       | BATS shell test suite                                            |
| `functions.sh`                 | Thin wrapper sourcing `src/_shared/functions.sh`                 |
| `install.sh`                   | Idempotent installer — wires hooks, tools, runtime deps          |
| `init.sh`                      | Per-project initialization (optional)                            |
| `update.sh`                    | Update logic (often re-executes install.sh)                      |
| `pre.sh`                       | Prerequisites check run before install/update (optional)         |
| `up.sh`                        | Post-startup script run after docker services are up (optional)  |
| `mcp.opencode.json`            | MCP server definition for auto-registration (optional)           |
| `external-modules.json`        | Declares external module dependencies for auto-wiring (optional) |

**Key patterns:**

- **Multi-agent orchestration**: DevBot classifies work by type/size, delegates to subagents (PO, Architect, Critic, Developer, Tester, Reviewer, Security, Scout) via structured protocol (`agent-communication` skill).
- **Planning → Implementation workflow**: `make-plan` + `implement-story` drive staged process: backlog (PO) → plan (Architect) → review (Critic) → approve (DevBot) → implement (Developer + Tester + Reviewer).
- **Memory vault**: `.agents/memory/` stores agent knowledge (latent notes, ADRs, PDRs, thinking, work) — captured automatically by `remember-session` hooks.
- **Plugin hooks**: OpenCode lifecycle hooks (`on-file_edited-*`, `on-tool_execute_before-*`, `on-session_error-*`, `on-session_idle-*`) for guards, format-md, auto-recover.
- **Entry point**: `bin/devbot` CLI (Bash) — subcommands: install, init, update, up, down, tool, module, models.
- **External modules**: Third-party agent skills/tools wired via `modules` config (e.g. addyosmani/agent-skills), cloned into `vendor/`, symlinked into `.opencode/`.
- **Local LLM**: Docker Compose runs Ollama for local inference (port 18434). Optional LiteLLM proxy.
- **Graph-based code analysis**: `graphify` tool produces codebase knowledge graphs in `graphify-out/`.

### Cascading `functions.sh` dependency chain

All modules share a single library via a cascading source chain:

```
src/_shared/functions.sh          ← root shared library (15+ utility functions)
  ├── src/agentic/*/functions.sh  ← thin wrapper: sources _shared (7 lines)
  ├── src/tools/*/functions.sh    ← thin wrapper: sources _shared (7 lines)
  └── bin/*.sh                    ← lifecycle scripts: source _shared directly
```

`src/_shared/functions.sh` provides: `_upsert_gitignore_section`, `_upsert_hook_section`, `_upsert_opencode_plugin`, `_run_module_prereqs`, `_pull_ollama_models`, `_devbot_get_disabled_modules`, `_check_python3`, `_fmt_duration`, output helpers (`_info`, `_ok`, `_skip`, `_warn`, `_error`, `_header_1/2/3`), `_step`.

Module-level `functions.sh` files are thin wrappers (7 lines) that resolve `MODULE_DIR` and source `../../_shared/functions.sh`. `bin/*.sh` scripts source `src/_shared/functions.sh` directly via `DEV_BOT_ROOT`.

### Docker Compose pattern

Docker compose files live under `src/tools/<tool>/docker-compose.yml` — not at project root:

| Tool    | Service | Port mapping            | Notes                                                |
| ------- | ------- | ----------------------- | ---------------------------------------------------- |
| ollama  | ollama  | `127.0.0.1:18434:11434` | Healthcheck: `ollama list`, volume: `storage/ollama` |
| litellm | litellm | `127.0.0.1:18000:4000`  | Depends on ollama `service_healthy`                  |

`bin/up.sh` and `bin/down.sh` **auto-discover** compose files via `find src/tools -maxdepth 2 -name 'docker-compose.yml'`, filter by `disabled_modules` config, and build `-f` flags for `docker compose`. If `gpu_enabled: true` in `.devbot.jsonc`, a `docker-compose.gpu.yml` is appended.

### MCP config pattern (`mcp.opencode.json`)

Seven agentic modules provide MCP servers via `src/agentic/<module>/mcp.opencode.json`. Each file defines a single MCP server entry with a top-level key:

```json
{
  "<mcp-key>": {
    "type": "local" | "remote",
    "command": ["...", "..."],   // local only
    "url": "https://...",        // remote only
    "enabled": true
  }
}
```

| Module          | Type   | Transport                          |
| --------------- | ------ | ---------------------------------- |
| graphify        | local  | `bash .opencode/graphify-serve.sh` |
| codebase-index  | local  | `npx opencode-codebase-index-mcp`  |
| qmd             | local  | `qmd mcp`                          |
| chrome-devtools | local  | `npx chrome-devtools-mcp@latest`   |
| playwright      | local  | `docker run mcp/playwright`        |
| context7        | remote | `https://mcp.context7.com/mcp`     |
| websearch       | remote | `https://mcp.exa.ai/mcp`           |

`bin/init.sh` auto-registers these into the project's `opencode.jsonc`: scans `src/agentic/*/mcp.opencode.json`, extracts the MCP key, checks for existing registration, substitutes `__GPU_ENABLED__` placeholder, and merges via `jq`.

### External module config pattern (`external-modules.json`)

Modules that depend on external git repositories (skills, agents, commands) declare them via `src/agentic/<module>/external-modules.json`. Each file defines one or more external module entries matching the `.devbot.jsonc` `modules` key format:

```json
{
    "<module-name>": {
        "url": "<git-url>",
        "paths": {
            "<type>": "<path>"
        }
    }
}
```

Entries are auto-merged into the root `.devbot.jsonc` `modules` config by `bin/up.sh` (via `_rebuild_external_module_config()`), which scans all enabled modules, collects their declarations, and adds missing entries idempotently. Disabled modules' declarations are skipped.

| Module           | Declared external modules |
| ---------------- | ------------------------- |
| external-modules | _(canonical spec holder)_ |

### `bin/` lifecycle delegation

The `bin/devbot` CLI delegates each subcommand to a corresponding `bin/<command>.sh` script. Each lifecycle script follows the same pattern: source `src/_shared/functions.sh`, then loop through `src/tools/*/` and `src/agentic/*/` running the matching script, respecting `disabled_modules` config.

| Command   | Script           | Flow                                                                                                    |
| --------- | ---------------- | ------------------------------------------------------------------------------------------------------- |
| `install` | `bin/install.sh` | `pre.sh` → `src/tools/*/install.sh` → `src/agentic/*/install.sh`                                        |
| `update`  | `bin/update.sh`  | git pull → `npm update` → `src/tools/*/update.sh` → `pre.sh` → `src/agentic/*/update.sh`                |
| `init`    | `bin/init.sh`    | `src/tools/*/init.sh` → `src/agentic/*/init.sh` → MCP registration → external modules                   |
| `up`      | `bin/up.sh`      | docker compose up (auto-discovered) → external module config rebuild → `src/**/up.sh` (auto-discovered) |
| `down`    | `bin/down.sh`    | docker compose down (auto-discovered)                                                                   |

**Disabled modules**: Config-driven via `.devbot.jsonc` (`disabled_modules` array). Per-project override in `.ai/devbot/devbot.jsonc` merged with global config. All lifecycle scripts filter by this list before running module/tool scripts.

## Tool entry points

- **`.ts` tools are authoritative** — agents/LLM invoke `.ts` tools directly via OpenCode tool palette. Business logic lives in `.ts` files.
- **`.sh` scripts are human CLI wrappers only** — thin entry points that delegate to `.ts` via `bun run`. Never contain business logic.
- **`.py` scripts are internal helpers** — called by `.ts` or `.sh` as subprocesses; never the primary entry point for agents.

## Critical conventions

- `.ai/` gitignored — never commit agent working state to project repo.
- `no-vcs/` NEVER read/modified by agents (enforced by `ignore.md`).
- JSONC format (JSON + comments, trailing commas) for all config files — parsed via `src/_shared/read_jsonc.py` (strips `//` and `/* */` comments), never raw `jq`.
- Symlink-based wiring: `.opencode/` skills/agents/commands are symlinks into `src/agentic/<module>/skills/` or `no-vcs/.opencode/` for external modules.
- **Plugin auto-wiring**: `src/tools/opencode/init.sh` (_link_plugins) auto-discovers `src/agentic/*/hooks/opencode/*.ts` files, symlinks them into `.opencode/plugins/`, and registers them in `opencode.jsonc` via `_upsert_opencode_plugin`. New modules with hooks need NO install/init script for hook wiring — just place the `.ts` file under `hooks/opencode/`.
- **Detached silent spawn pattern**: When a hook needs to run a CLI command without blocking the TUI or leaking output, use `Bun.spawn` with the array `stdio` form: `Bun.spawn(["cmd", "arg"], { cwd: project.worktree, stdio: ["ignore", "ignore", "ignore"], detached: true }).unref()`. The array `["ignore", "ignore", "ignore"]` maps to `[stdin, stdout, stderr]`. Do NOT use `await $` (BunShell) — it blocks the event loop and leaks output to TUI. Reference: `src/agentic/memory/hooks/opencode/on-file_edited-reindex-memories.ts` and `src/agentic/devbot-up/hooks/opencode/on-session_created-devbot-up.ts`.
- BATS for shell module tests — each module owns `tests/<module>_tests.bats`.
- Module lifecycle: each has `install.sh` (idempotent) + optional `init.sh`, `update.sh`, `pre.sh`, `up.sh`.
- Conventional commit messages enforced by git hooks.
- `graphify-out/` and `node_modules` gitignored.

## Rough edges

- Two OpenCode config files: `opencode.dist.jsonc` (canonical dist at `src/tools/opencode/opencode.dist.jsonc`) vs runtime `opencode.jsonc` (gitignored at root) — confusion risk about which authoritative.
- Symlink-heavy structure → some tools fail to follow targets (glob, qmd index) — verified gotchas in memory.
- `.opencode/index/` under `no-vcs/` (bypassed by glob/grep) — index ops must use dedicated codebase-search tools.
- Git blob corruption incidents documented in memory — index-only corruption recoverable via `git rm --cached` + `git reset HEAD`.
- AI session idling triggers `remember-session` plugin automatically → simultaneous hook execution if session resumes while hook runs.

## Dependencies

| Dependency                             | Purpose                                         |
| -------------------------------------- | ----------------------------------------------- |
| `@opencode-ai/plugin` (^1.14.50)       | OpenCode plugin SDK                             |
| Docker + Docker Compose                | Local dev services (Ollama, LiteLLM)            |
| Ollama                                 | Local LLM inference                             |
| uv (Python package manager)            | Python tool execution (graphify, format-md)     |
| npm / node                             | OpenCode runtime, TypeScript tools              |
| BATS                                   | Shell test framework                            |
| jq / yq                                | JSON/YAML parsing in shell scripts              |
| ripgrep (rg)                           | Fast content search (used by tools/search-code) |
| Git hooks (post-commit, post-checkout) | Auto-trigger memory capture and graph re-index  |
