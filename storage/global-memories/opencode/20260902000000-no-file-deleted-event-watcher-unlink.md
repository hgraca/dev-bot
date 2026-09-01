---
date: 2026-09-02
keywords: ["opencode", "hook", "file.deleted", "watcher", "unlink"]
trigger-on: ["opencode-file-deleted", "file-watcher-unlink"]
---

## opencode SDK has no file.deleted event — deletes arrive as file.watcher.updated with event "unlink"

The `@opencode-ai/sdk` Event union contains `file.edited` and
`file.watcher.updated` (properties `{ file, event: "add"|"change"|"unlink" }`)
but NO `file.deleted` type. A file deletion fires `file.watcher.updated` with
`properties.event === "unlink"`. A hooks adapter that only dispatches
`file.edited` (e.g. devbot's on-hooks.ts) silently misses deletions — stale
index/docs survive until the next edit-triggered cleanup. Fix pattern: extract
a pure mapper `deletedFileFromWatcher(event)` returning the file path only for
type `file.watcher.updated` + event `"unlink"`, dispatch a synthetic
"file.deleted" hook event from it, and let hooks.json declare a
`file.deleted` hook (e.g. reindex-on-delete). Unit-test the mapper against the
SDK shapes. Also note: no `file.created`/`file.renamed` events exist either —
watcher "add"/"change" cover creation and edits.
