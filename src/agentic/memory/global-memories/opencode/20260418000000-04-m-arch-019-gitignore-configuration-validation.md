---
date: 2026-04-18
keywords: ["opencode"]
---

## M-ARCH-019: Gitignore configuration validation

Attempting to commit files that should be tracked but are gitignored
Validate .gitignore patterns match documented expectations. Missing exceptions (like !storage/opencode.jsonc) can block legitimate file tracking
