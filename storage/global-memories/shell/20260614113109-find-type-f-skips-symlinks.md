---
date: 2026-06-14
keywords: ["shell", "find", "symlink", "type-f", "opencode"]
---

## find -type f does not match symlinks even when target is a regular file

`find -type f` only matches actual regular files (S_IFREG). Symlinks to regular files have type `l` (S_IFLNK) and are NOT matched by `-type f`, even though stat/lstat would show them pointing to a regular file.

When scanning a directory like `.opencode/tools/` that contains symlinks (e.g., `tree.ts -> ../../../src/agentic/tree/tools/tree.ts`), `find -type f -name '*.ts'` silently returns nothing. Fix: add `-o -type l` to also match symlinks: `find ... \( -type f -o -type l \)`. Alternatively use `find -L` to follow symlinks and match the target file type, but `-L` also changes directory traversal behavior.

Context: dev-bot's `.opencode/tools/` stores tool definitions as symlinks back to `src/agentic/<module>/tools/<tool>.ts`. Initial implementation of `bin/agentic-tools.sh` used `-type f` which found zero tools.
