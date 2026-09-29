---
date: 2026-09-29
keywords: ["sqlite", "vacuum", "freelist", "disk-reclaim", "auto-vacuum"]
trigger-on: ["sqlite-vacuum", "sqlite-db-maintenance"]
---

## VACUUM costs the whole file size, not the bytes you reclaim

`VACUUM` rewrites the entire database file: it is O(file size), essentially independent of how much the preceding `DELETE` freed, and single-threaded and CPU/I-O bound. Measured case: deleting five rows' worth of data reclaimed 7.27 MB from a 7.8 GB file and took 3m 12s — the same order of cost as a run that reclaimed 9.9 GB of the same file. So `VACUUM` must never sit on a hot or unattended path (a session-exit hook, a request handler, a cron that fires per unit of activity); gate it on reclaimable bytes instead — only when `PRAGMA freelist_count * page_size` exceeds a threshold — or run it as a deliberate operator action. Deletion alone does not shrink the file but is enough to stop it growing: SQLite reuses freelist pages for new writes, so the file plateaus at its high-water mark. Note also that with `PRAGMA auto_vacuum = NONE` (the default) full `VACUUM` is the _only_ way to return space to the OS — `PRAGMA incremental_vacuum` requires `auto_vacuum = INCREMENTAL`/`FULL`, which only a one-time rebuild can set. `VACUUM` additionally needs roughly the file size again in free temp space, so on a multi-GB database it can fail for disk reasons where the deletes alone would have succeeded.
