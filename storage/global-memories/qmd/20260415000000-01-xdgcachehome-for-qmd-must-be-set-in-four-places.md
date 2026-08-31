---
date: 2026-04-15
keywords: ["qmd", "xdg_cache_home"]
---

## `XDG_CACHE_HOME` for QMD must be set in four places

Because `XDG_CACHE_HOME` is a global variable (affects all XDG-compliant apps), it must NOT be exported globally. Instead set it in every context where `qmd` runs:

1. **DevBot scripts** (`init-project.sh`, `update.sh`): `export XDG_CACHE_HOME="${DEVBOT_ROOT}/storage"` at the top of the qmd section
2. **MCP server** (`opencode.dist.jsonc`): `"environment": { "XDG_CACHE_HOME": "{file:.ai/devbot/secrets/qmd-cache-home}" }`
3. **Secrets file** (`storage/secrets/qmd-cache-home`): written by `install.sh` with the absolute DevBot storage path; referenced by the dist config
4. **Shell RC** (`~/.bashrc` / `~/.zshrc`): `qmd() { XDG_CACHE_HOME="<path>" command qmd "$@"; }` wrapper function written by `write-env.sh`
