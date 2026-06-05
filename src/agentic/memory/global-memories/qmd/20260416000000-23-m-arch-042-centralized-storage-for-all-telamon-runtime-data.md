---
date: 2026-04-16
keywords: ["qmd", "xdg_cache_home"]
---

## M-ARCH-042: Centralized storage for all DevBot runtime data

QMD, Ogham, Obsidian, and other tools generate cache files, indexes, and secrets. Storing them in <devbot-root>/storage instead of system-wide locations enables multi-project isolation and easier backup.
Use environment variables (XDG_CACHE_HOME, DATABASE_URL, etc.) to redirect tool cache and config to a centralized DevBot storage directory. This keeps the user's home directory clean and enables per-project or per-tool configuration overrides.
