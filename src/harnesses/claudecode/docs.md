---
title: "Claude Code"
description: "The Claude Code harness — five-phase hook dispatcher, module integrations, and stats."
---

Claude Code is one of the two agent runtimes DevBot plugs into. Each harness lives in `src/harnesses/<name>/` and is self-contained — it owns its hooks, wiring and config templates, while business logic stays in the agentic modules' `tools/`.

## The adapter

`src/harnesses/claudecode/hooks/on-hooks.py` is a **five-phase dispatcher** — `pre-tool` / `post-file` / `post-bash` / `stop` / `startup` — because Claude Code's hook events are separate registrations with no unified event stream. It reads every `src/agentic/*/hooks.json` manifest and maps the six semantic events onto the phases it registers.

Hook commands are anchored to Claude Code's `${CLAUDE_PROJECT_DIR}` placeholder, so they resolve from any session cwd. Session start publishes `DEV_BOT_SESSION_ID` and the primary agent name to the Bash preamble. `CLAUDE_ENV_FILE` is not available to tool events, so the `pre-tool` phase instead returns `PreToolUse` `updatedInput` for a subagent's Bash command, prefixing `export DEV_BOT_AGENT_NAME=<agent_type>;` — the payload's `agent_type` identifies the caller without relying on the shared preamble. The primary name is resolved from `.claude/settings.json`, never hard-coded.

Prerequisites on the machine running Claude Code:

- **bun** — runs the `tools/*.ts` hooks (`curl -fsSL https://bun.sh/install | bash`)
- **jq** — parses the hook event JSON from stdin (`brew install jq`, `apt-get install jq`, or `dnf install jq`)

Registration is handled centrally by `src/harnesses/claudecode/hooks.json` — modules declare only their manifest, never a per-harness hook config.

## Module integrations

- **guards** — registered via `PreToolUse` with matcher `Bash`. The hook reads the event JSON, extracts the command, runs `guards.ts` against the guard rules, and emits a deny decision with the rule's reason when it matches. Non-matching commands pass through.
- **format-md** — registered via `PostToolUse` with matcher `Edit|Write`. The hook extracts `file_path`; when it ends in `.md` it runs `format-md.py` on it, and non-markdown files are silently skipped. The `post-file` phase reads the module manifest to decide what to run.
- **graphify** — exposed as an MCP server (`src/agentic/graphify/tools/claudecode/mcp-server.js`). It runs in **proxy mode** when `graphify-out/graph.json` exists (spawning `graphify.serve` and bridging stdio) and in **stub mode** otherwise, advertising the tool names and telling you to run `graphify update` first.

## Stats

`src/harnesses/claudecode/stats.py` parses the session transcripts under `~/.claude/projects/<slug>/**/*.jsonl` (including subagents). Tokens come from each assistant message's `usage`; transcripts carry no cost data, so `cost_kind` is `null` and the report shows a Tokens column instead of Cost. It aggregates `Bash`/`Skill`/`Grep`/`Glob` arguments with the same normalisation as the OpenCode adapter.

The adapter contract is harness-agnostic — see [the `devbot stats` reference](/modules/tools/devbot-cli#writing-a-stats-adapter).

## Configuration

`.claude/settings.json` carries the session agent (the dispatcher reads its `agent` key to name the primary agent); the hook registrations live in `src/harnesses/claudecode/hooks.json` and are wired by `init.sh`.

## See also

- [OpenCode](/modules/harnesses/opencode) — the other harness
- [Hooks](/hooks) — the manifest schema and semantic events
