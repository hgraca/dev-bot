---
date: 2026-11-17
keywords: ["devbot", "locks", "gitignore", "generated-state"]
aliases: ["lock file flashing in project root", "mcp-sync lock location"]
---

# Locks and other generated session state belong under the devbot dir, not beside tracked config

## The trap

`mcp-sync` took its mutex at `opencode.jsonc.mcp-sync.lock` — a directory, because `mkdir` is the atomic primitive. That put a directory that is created and removed on every poll next to a tracked file: it flashed in the project root, in `git status` and in editor file trees, and it looked like a stray backup.

## The rule

Anything a plugin creates and deletes while it runs belongs under `<devbot_dir>`: use `<devbot_dir>/locks/<name>.lock` for mutexes, `<devbot_dir>/logs/` for logs, `<devbot_dir>/mcp-runtime/` for generated manifests. Create the folder on demand (`recursive: true`) and never delete it — an empty `locks/` is cheaper than a directory that blinks.

## Keep the ignore list in step

`src/tools/devbot-cli/init.sh` owns the managed `# >>> DEVBOT` block in `.git/info/exclude`. A new generated path is not done until it is listed there **and** asserted in `src/tools/devbot-cli/tests/devbot_tests.bats`, otherwise `devbot init` leaves it untracked-but-offered-to-git on every project. `mcp-runtime` and `locks` are both in that list; the same pass should carry any future one.
