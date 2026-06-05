---
date: 2026-04-20
keywords: ["git", "commit"]
---

## M-FLOW-053: Atomic commit splitting requires systematic approach with verification

Splitting 3 features from single staged changeset into separate commits
Save original diff, reset to clean state, then for each story: apply only that story's changes to shared files, stage, commit, restore full state. Verify final result matches original using content hash comparison of sorted diff lines.
