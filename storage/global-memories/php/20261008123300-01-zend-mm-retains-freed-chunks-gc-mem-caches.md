---
date: 2026-10-08
keywords: ["php", "gc_mem_caches", "zend-mm", "memory", "queue-worker"]
aliases: ["rss not released", "fragmentation", "worker memory retained", "zend_mm_gc"]
---

## Long-lived PHP workers retain freed-but-fragmented memory; `gc_mem_caches()` returns it

When a long-running PHP process (queue worker, Octane/Swoole, a crond loop) transiently allocates a
large amount of memory (hundreds of MB to several GB) across many interleaved allocations and then
releases it, the Zend memory manager keeps the now-empty chunks on its free list. RSS stays at the
peak even though `memory_get_usage()` (live) falls back to near baseline — so it looks like a leak
but nothing is referenced. `gc_collect_cycles()` does **not** help (it only frees reference cycles);
`gc_mem_caches()`, the userland binding of `zend_mm_gc`, consolidates free chunks and returns them to
the OS. Measured on PHP 8.4 with an export-shaped workload (1.5M rows → OpenSpout XLSX → read back →
unset every local): peak RSS 869 MB → 792 MB after all references were freed (live only 9.5 MB) →
792 MB after `gc_collect_cycles()` (no change) → **48 MB after `gc_mem_caches()`** (~96% reclaimed).
A trivial "allocate 1.2 GB of strings, then unset" returns to baseline with *no* GC call — the
retention only appears once allocations interleave across chunks, which any real workload does. So:
in a worker that may handle a large transient allocation, call `gc_mem_caches()` on the loop after
the job, threshold-gated (`memory_get_usage(true) > cap`) so a busy worker handling small messages
does not pay the consolidation cost. Caveat: this reclaims memory only *after* the allocation — the
peak and any `memory_limit` OOM are unchanged, so it fixes residency, not the ceiling. Only relevant
to long-lived processes; PHP-FPM frees per request.
