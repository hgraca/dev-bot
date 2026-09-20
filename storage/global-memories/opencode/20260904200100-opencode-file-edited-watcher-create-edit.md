---
date: 2026-09-04
keywords: ["opencode", "file.edited", "file.watcher.updated", "plugin", "create"]
---

## opencode tool writes publish file.edited + a companion file.watcher.updated (add|change); file.edited alone cannot distinguish create from edit

When opencode's `write`/`edit`/`apply_patch` tools modify a file they publish
`file.edited` (`properties: {file}` — no create-vs-edit flag) AND a companion
`file.watcher.updated` whose `properties.event` is `"add"` (create) or
`"change"` (edit); `apply_patch` also publishes `"unlink"`/`"add"` for
deletes/moves. External (non-tool) file changes surface only as
`file.watcher.updated`. A plugin that must treat creates differently from
edits therefore cannot rely on `file.edited` alone: pair each `file.edited`
with its companion watcher event, with a short settle-timeout fallback that
dispatches anyway for opencode builds that publish only `file.edited`.

Second gotcha in the same area: opencode's edit tool matches
indentation-insensitively via fuzzy replacers, so any out-of-band rewrite of a
file between the agent's Write and its next Edit (e.g. a background formatter
normalizing the fresh file) lets the agent's stale-indentation hunk get
spliced in silently, producing invalid markup the formatter then refuses to
repair. Never normalize a freshly-written file asynchronously — format only on
edits, or use opencode's native in-tool formatters (which re-sync the diff,
though they too cannot repair an unparseable splice).
