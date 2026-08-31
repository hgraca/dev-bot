---
date: 2026-04-15
keywords: ["qmd", "xdg_cache_home"]
---

## Shell function wrapper for env-scoped CLI tools

When a CLI tool needs an env var set on every invocation but setting it globally would affect other tools, use a shell function wrapper:

```bash
qmd() { XDG_CACHE_HOME="/absolute/path" command qmd "$@"; }
```

The `command` builtin bypasses the function and calls the real binary, preventing infinite recursion. This pattern is idempotent when written with a marker comment and refreshed in-place by the installer.
