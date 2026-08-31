---
date: 2026-05-15
keywords: ["qmd", "symlink", "fast-glob", "followSymbolicLinks"]
---

## QMD does not follow symlinks — fast-glob hardcoded to followSymbolicLinks:false

`qmd update` silently skips any directory that is a symlink. Root cause: QMD's `reindexCollection` calls `fastGlob` with `followSymbolicLinks: false` hardcoded in `dist/store.js` — no config option exists. Workaround: register the real target directory as its own QMD collection instead of relying on the symlink path. Confirmed in QMD v2.1.0.
