---
date: 2026-09-02
keywords: ["devbot", "harness", "hooks", "session.created", "memory", "prune"]
---

# Cross-harness start-of-session work: use session.created, not session.idle or delete events

Audit-28/29/30 (opencode 1.18.26 + claudecode): deleting a memory note via
external `bash rm` never dispatched any delete event — opencode emits no
watcher unlink for external deletions, and claudecode has no delete event at
all. A `file.deleted` hook can therefore never fire; the whole watcher→
`file.deleted` mapping in `src/harnesses/opencode/hooks/on-hooks.ts` was dead
code and was removed.

Both harness adapters DO dispatch **`session.created`**: opencode on session
start, claudecode maps its `SessionStart` hook → `startup` phase →
`session.created` (see `src/harnesses/claudecode/hooks/on-hooks.py`). Use that
event for any start-of-session maintenance. The memory index self-heal prune
(`qmd cleanup && qmd update`, no embed — `reindex-memories.mcp.sh prune`)
therefore runs on `session.created` (`reindex-memories-prune-start` in
`src/agentic/memory/hooks.json`): a note deleted mid-session is pruned at the
next session start. `session.idle` only maps to claudecode's `Stop` (end of
session), so it is not a reliable cross-harness "idle" signal.

## Superseded for the memory prune (audit-36, 2026-09-03)

The delete→prune self-heal no longer uses `session.created`. It moved to the
harness start scripts (`src/harnesses/{opencode,claudecode}/start.sh` →
`_devbot_prune_memories_detached` in `src/_shared/functions.sh`), fired
**detached before the harness boots**, and the `reindex-memories-prune-start`
hook was removed from `src/agentic/memory/hooks.json`. Reasons: (1) opencode
`session.created` fires only for the first session of a process, so later
sessions in the same process never pruned (audit-34 NOTE-8); (2) running at
harness boot added contention that, together with the concurrent launch of all
MCP servers, pushed chrome-devtools/playwright past the client's 30s connect
budget (audit-35 FAIL). The start.sh prune fires per `devbot` launch and gives
qmd a head start ahead of the MCP fleet boot. `session.created` remains a valid
event for other start-of-session maintenance that must also cover directly
launched harnesses.
