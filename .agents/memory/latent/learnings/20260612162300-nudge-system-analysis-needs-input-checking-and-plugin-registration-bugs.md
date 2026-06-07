---
date: 2026-06-12
keywords: ["devbot", "nudge", "NEEDS_INPUT", "plugin", "session.idle", "opencode.jsonc"]
---

# Nudge system analysis: NEEDS_INPUT checking, bugs found

Comprehensive exploration of the dev-bot nudge system across three plugins (agent-communication, remember-session, auto-recover). Full report in prior thinking file.

## Key findings

**NEEDS_INPUT checking is correct**: Both idle plugins correctly suppress when last assistant message ends with NEEDS_INPUT. agent-communication uses `MARKER_RE` (includes NEEDS_INPUT); remember-session only fires on FINISHED! (NEEDS_INPUT blocks it). Auto-recover doesn't need NEEDS_INPUT check (fires on session.error).

**Critical bug — remember-session plugin silently broken**: `opencode.jsonc` line 12 registers `".opencode/plugins/on-session_idle-remember-session"` without `.ts` extension. The actual symlink is `on-session_idle-remember-session.ts`. opencode silently skips missing plugin files — no error reported. Same bug in `opencode.no-vcs.jsonc`. Plugin likely never loads.

**No init.sh registration**: `memory/init.sh` only registers the reindex-memories plugin. There's no init.sh call that registers the remember-session idle plugin in opencode.jsonc. If opencode.jsonc is regenerated, the entry is lost.

**Historical bug (fixed)**: `lastAssistantMessageEndsWithFinished` in remember-session hook iterated ALL assistant messages instead of just the last. When latest ended with NEEDS_INPUT or BLOCKED, it would fall through to an older FINISHED!. Fixed in commit 85cb702 (2026-06-11) by adding `return false` after checking the last assistant message's parts.

**Counter inconsistency**: agent-communication stores counters in `.agents/logs/` while auto-recover stores them in `.agents/memory/thinking/`. Different cleanup patterns.
