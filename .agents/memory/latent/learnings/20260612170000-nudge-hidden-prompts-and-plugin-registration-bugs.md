---
tags: [latent, investigation, plugin, nudge, hidden, registration]
description: Investigation into nudge system bugs — hidden prompts, missing .ts in opencode.jsonc, missing init.sh registration
---

# Investigation: Nudge System Bugs

2026-06-12

## Symptoms

User reported:
1. Plugins send nudges even when last assistant reply ends with `NEEDS_INPUT:`
2. No nudge prompts visible in the UI

## Root Causes Found

### Bug 1: Missing `.ts` Extension (CRITICAL)

`opencode.jsonc` line 12 and `opencode.no-vcs.jsonc` line 12 had:
```
".opencode/plugins/on-session_idle-remember-session"
```
Missing `.ts` extension. The actual file is `on-session_idle-remember-session.ts`.
Impact: remember-session plugin silently never loads. Memory capture on idle broken.

**Fix applied**: Added `.ts` extension to both files.

### Bug 2: Missing init.sh Registration (WARNING)

`src/agentic/memory/init.sh` only registered `on-file_edited-reindex-memories.ts`.
No `_upsert_opencode_plugin` call for `on-session_idle-remember-session.ts`.
If `opencode.jsonc` is regenerated (fresh install), the idle plugin entry is lost.

**Fix applied**: Added registration call alongside the existing one.

### Bug 3: Hidden Prompts (DESIGN)

All three plugin nudges use `{ hidden: true, synthetic: true }` in `client.session.prompt()`.
- agent-communication: `{ hidden: true, source: "agent-communication" }`
- remember-session: `{ hidden: true, source: "remember-session-plugin" }`
- auto-recover: `{ hidden: true, source: "auto-recover" }`

The `hidden: true` flag intentionally hides the prompt from the chat UI, but it also means:
- The user can't see nudge activity
- The user interprets "nothing in the UI" as "nudges not being sent"
- Hidden prompts may or may not be returned by `client.session.messages()` — if excluded, `hasEnforcerTag()` can't find its own tag, breaking the loop-prevention guard

### Bug 4: Suspected Timing Race (SUSPECTED)

The `detectTerminalMarker()` function in `agent-communication-helpers.js` correctly detects NEEDS_INPUT: via regex `/^(FINISHED!|BLOCKED:|NEEDS_INPUT:|PARTIAL:)/` on the last non-empty line. However, a timing race is possible: if `session.idle` fires before the final assistant message is committed to session history, the plugin sees a stale message without a marker and nudges.

## Key Code Paths

| File                                                                       | Lines       | Role                                        |
|----------------------------------------------------------------------------|-------------|---------------------------------------------|
| `src/agentic/agent-communication/tools/agent-communication.js`             | 36-166      | Plugin — nudge engine                       |
| `src/agentic/agent-communication/tools/agent-communication-helpers.js`     | 13, 150-171 | `MARKER_RE` regex, `detectTerminalMarker()` |
| `src/agentic/memory/hooks/opencode/on-session_idle-remember-session.ts`    | 191-310     | Remember-session plugin                     |
| `src/agentic/auto-recover/hooks/opencode/on-session_error-auto-recover.ts` | 1-103       | Auto-recover plugin                         |

## Related ADRs/Patterns

- `20260507000000-01-idle-driven-plugin-loop-prevention-three-layer-guard.md`
- `20260510000000-06-replace-idle-fired-plugin-with-git-post-commit-hook-inherited.md`
- `20260510000000-14-plugin-prompt-text-changes-require-opencode-restart-to-activate.md`
