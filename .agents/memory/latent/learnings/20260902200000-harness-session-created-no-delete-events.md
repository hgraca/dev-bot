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
