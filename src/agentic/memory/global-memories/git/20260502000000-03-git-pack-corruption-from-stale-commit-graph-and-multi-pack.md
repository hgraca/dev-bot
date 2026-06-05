---
date: 2026-05-02
keywords: ["git", "commit", "corruption"]
---

## Git pack corruption from stale commit-graph and multi-pack-index

When you delete old `.git/objects/pack/*.pack` files and create a new pack (e.g. via `git rev-list --objects --all | git pack-objects`), the stale `commit-graph` (in `.git/objects/info/commit-graph` or `.git/objects/info/commit-graphs/`) and `multi-pack-index` files still reference objects from the deleted packs. This causes `git fsck` to report thousands of "Could not read" and "failed to load pack entry" errors — making it look like the new pack is corrupt when it's actually fine.
Fix: After replacing pack files, always delete: `.git/objects/info/commit-graph`, `.git/objects/info/commit-graphs/`, `.git/objects/pack/multi-pack-index`, and any `.rev` files for old packs. Then `git fsck` will pass clean. Also delete `.git/logs/` (reflogs) if they reference now-unreachable commits.
