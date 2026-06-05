---
date: 2026-04-16
keywords: ["obsidian"]
---

## M-ARCH-004: Symlink-based project wiring for shared skills and secrets

DevBot skills, plugins, and secrets need to be shared across projects while maintaining per-project isolation
Use symlinks to connect project-local .ai/devbot/ to centralized storage/: .ai/devbot/memory → storage/obsidian/<project>, .ai/devbot/secrets → storage/secrets, opencode.jsonc → storage/opencode.jsonc. This enables single-source-of-truth for shared resources while preserving per-project vaults and configs.
