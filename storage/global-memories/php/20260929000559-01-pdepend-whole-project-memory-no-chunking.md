---
date: 2026-09-29
keywords: ["php", "pdepend", "memory-limit", "oom"]
trigger-on: ["pdepend-large-project"]
---

## PDepend OOMs at a container's default 128M on a large tree, and its file list must not be chunked

PDepend holds the whole project in memory, so a stock `php:*-cli` image (`memory_limit=128M`) exhausts on a mid-size repo: a 5,196-file PHP tree died after 64 s with a fatal inside `PDepend/Util/Cache/Driver/FileCacheDriver.php` and emitted **zero bytes** of output, which a caller that only collects stderr reports as a silent empty result. Raise the limit (`php -d memory_limit=1024M`) — 1 GB completed that same 5,196-file run in 106 s with 17,884 units and no errors. Do **not** work around it by chunking the file list: `ca`/`ce`/`cbo`/`dit` are whole-project coupling metrics, so per-batch analysis silently corrupts them — the split run looks successful while quietly losing every cross-file edge.
