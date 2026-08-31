---
date: 2026-04-16
keywords: ["mcp", "server"]
---

## M-ARCH-043: Symlink shared configuration to avoid duplication across projects

Multiple projects need access to the same MCP servers, skills, and secrets. Symlinking opencode.jsonc and .ai/devbot/secrets from DevBot storage to each project reduces maintenance burden.
Use symlinks for shared configuration files (opencode.jsonc, secrets directory). For projects with existing configs, use a merge script to add DevBot settings without overwriting project-specific configuration.
