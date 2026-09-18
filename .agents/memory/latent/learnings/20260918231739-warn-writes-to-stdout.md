---
date: 2026-09-18
keywords: ["functions.sh", "warn", "stdout", "stderr", "cli"]
---

# `_warn` writes to stdout — redirect it at the call site

`src/_shared/functions.sh` defines `_warn()` with a plain `echo` (no `>&2`), unlike `_error` and `_fatal` which redirect to stderr. A caller inside a command whose stdout is machine-readable output — e.g. `bin/stats.sh`, which pipes canonical JSON into the renderer — must therefore write `_warn "…" >&2`, or the warning is injected into the report. `_info` is the same (stdout) and is redirected explicitly wherever it is used. Changing `_warn` itself would alter every caller's behaviour, so the redirect stays at each call site; `bin/stats.sh` carries a comment marking its `>&2` as load-bearing.
