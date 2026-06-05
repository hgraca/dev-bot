---
date: 2026-04-15
keywords: ["qmd", "xdg_cache_home"]
---

## QMD index path is controlled via `XDG_CACHE_HOME` only

QMD has no `--db-path` flag or `QMD_HOME` env var. The only way to redirect its index (and model cache) away from `~/.cache/qmd/` is `XDG_CACHE_HOME`. Setting it to `${DEVBOT_ROOT}/storage` puts both `storage/qmd/index.sqlite` and `storage/qmd/models/` under DevBot's storage tree (all gitignored by `storage/*`).
