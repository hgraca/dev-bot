---
date: 2026-11-06
keywords: ["opencode", "session-storage", "diagnostics", "sqlite", "tab-switching"]
aliases: ["slow tab switch", "session payload bloat", "workspace diagnostics map"]
trigger-on: ["opencode-session-payload"]
---

## opencode session parts carry a whole-workspace LSP diagnostics map

opencode attached `state.metadata.diagnostics` to every `write`/`edit` tool part: a map of every file in the workspace, not just the written one. In a 28-repo checkout that measured 114,564 paths and ~18 MB per call, with only 6 entries holding an actual diagnostic. It is stored twice - in `part.data` and again inside the `event` replay journal (`$.part.state.metadata.diagnostics`) - so a 15 GB `opencode.db` was ~99% this one field.

Opening a session replays all of it. A 453 MB session took ~35 s of load (`opencode export` measured 43 s wall / 34 s user), which is why switching to an old tab felt frozen. The `opencode-tabs` plugin only calls `route.navigate()`, so the tab plugin is never the cause - the reload is.

Fix: strip the field from both tables (`json_remove`) and VACUUM. A 447 MB session drops to 0.3 MB of stored payload and a 14.2 GB database to ~1.6 GB. `devbot prune --db` now does this before the age prune (`src/harnesses/opencode/strip_opencode_diagnostics.py`). Newer opencode builds no longer write the map - it is legacy data, so a fresh session cannot reintroduce the bloat.

Diagnostics: `SELECT name, SUM(pgsize)/1024/1024 mb FROM dbstat GROUP BY name ORDER BY mb DESC` finds the heavy tables, and `length(json_extract(data,'$.state.metadata.diagnostics'))` sizes the field per row.
