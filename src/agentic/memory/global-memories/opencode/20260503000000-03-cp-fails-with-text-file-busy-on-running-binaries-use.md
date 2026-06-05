---
date: 2026-05-03
keywords: ["opencode", "tool"]
---

## `cp` fails with 'Text file busy' on running binaries — use `mv`

`cp newbinary /path/to/running-binary` fails with ETXTBSY because the kernel locks the inode of a running executable. Fix: `cp new dest.new && mv -f dest.new dest` — `mv` (rename) replaces the directory entry atomically while the old inode stays open for the running process. The running process continues using the old binary; next launch uses the new one.
