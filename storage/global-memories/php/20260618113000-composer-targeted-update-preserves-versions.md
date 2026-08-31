---
date: 2026-06-18
keywords: ["php", "composer", "version-pinning"]
---

## Targeted composer update with specific packages preserves existing versions

Running `composer update <package1> <package2> ...` adds only the specified packages and their transitive dependencies to the lock file while leaving all existing packages at their current versions. The lock operation output shows `0 updates, 0 removals` for existing packages. This is the correct approach when adding new packages to a frozen lock file — avoids unintended upgrades of unrelated packages that a bare `composer update` would trigger.
