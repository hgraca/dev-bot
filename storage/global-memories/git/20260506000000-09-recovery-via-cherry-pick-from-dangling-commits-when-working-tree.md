---
date: 2026-05-06
keywords: ["git", "commit", "blob", "corruption"]
---

## Recovery via cherry-pick from dangling commits when working-tree SHA mismatch blocks `git hash-object -w`

When L1027's `git hash-object -w` recovery fails because `git hash-object <path>` produces a different SHA than the missing blob (i.e. working tree has been modified since the corrupt commit was made), the L1027 caveat says "recover from origin instead". But if the corrupt commits are local-only (ahead of origin), there's a third option: **cherry-pick from dangling commits**. After a hard reset to escape corruption, dangling commits remain reachable for ~30 days (until `git gc --prune`). Workflow: (1) `git stash push -u -m "WIP"` to clear the working tree; (2) `git cherry-pick <SHA1> <SHA2> ...` for each dangling commit in order; (3) cherry-pick succeeds for any commit whose tree references blobs that ARE present, fails on the first commit that needs the missing blob — at which point the index ends up partially staged, useful for hand-finishing the missing commit. Validated this session: tasks 3, 4, 4-fix, 5 cherry-picked clean from dangling commits after `git reset --hard 6977fb2`; task 6 (which had the missing test-file blob `07b17a8c8...`) failed at cherry-pick — recovered by hand-applying staged changes from stash. Cross-ref L1027, L1042. See [[memories]].
