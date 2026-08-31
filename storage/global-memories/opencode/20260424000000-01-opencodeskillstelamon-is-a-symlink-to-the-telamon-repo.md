---
date: 2026-04-24
keywords: ["opencode"]
---

## .opencode/skills/devbot is a symlink to the devbot repo

The `.opencode/skills/devbot` directory is a symlink to `/home/herberto/Development/hgraca/devbot/src/skills`. You cannot `git add` files through the symlink from the message-bus repo — git will fail with "pathspec beyond a symbolic link". To commit skill file changes, switch to the devbot repo at `/home/herberto/Development/hgraca/devbot` and commit there.
