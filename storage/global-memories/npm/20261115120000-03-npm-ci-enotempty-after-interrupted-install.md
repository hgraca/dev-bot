---
date: 2026-11-15
keywords: ["npm", "npm ci", "ENOTEMPTY", "node_modules"]
---

## An interrupted `npm ci` leaves a tree that `npm ci` refuses to replace

Killing an install (timeout, OOM, kill) leaves `node_modules` in a state where the next `npm ci` fails with `ENOTEMPTY: directory not empty, rmdir .../node_modules/<pkg>/<dir>` instead of repairing it. The same symptom appears when two installs run concurrently on one directory — one rewrites while the other deletes, and npm reports ENOTEMPTY on its own rmdir. Fix both: delete `node_modules` before `npm ci` (`fs.rm(..., {recursive:true, force:true})`), and never let two builds of the same tree overlap — serialise them behind a "running" flag rather than a bare `setInterval`.
