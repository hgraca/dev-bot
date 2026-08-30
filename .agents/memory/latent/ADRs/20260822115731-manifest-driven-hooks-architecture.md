---
date: 2026-08-22
keywords: ["devbot", "hooks", "manifest", "architecture"]
see: ["ADRs/20260822095752-harness-agnostic-hook-logic-in-tools.md"]
---

## Hooks are manifest-driven: hooks.json + tools/ + one generic adapter per harness

Option A is complete. Hooks are now declared in a per-module `hooks.json` manifest (`{id, event, match{file,content,tool,command}, run, blocking}`) and the business logic lives once in the module's `tools/` entry. Each harness has one generic adapter that reads all manifests and wires them: opencode's `src/harnesses/opencode/hooks/on-hooks.ts` maps the six semantic events (`file.edited`, `command.before`, `command.after`, `session.idle`, `session.error`, `session.created`) to the plugin API, and claudecode's `src/harnesses/claudecode/hooks/on-hooks.py` is a five-phase dispatcher (`pre-tool`/`post-file`/`post-bash`/`stop`/`startup`). All per-module hooks were deleted; harness modules are now self-contained. Two exceptions stay hand-written because they don't fit the "run a command" model: `auto-recover` (opencode injects the recovery prompt via `client.session.prompt`; claudecode uses a two-phase PostToolUse→Stop trigger flow). Rule for future hook work: write a `tools/` entry plus a `hooks.json` manifest — never a per-harness hook file.
