---
date: 2026-10-09
keywords: ["shell", "shellcheck", "SC2034", "bash", "library"]
aliases: ["SC2034 sourced file", "shellcheck unused variable library"]
trigger-on: ["extract-shared-shell-library"]
---

## Extracting a sourced shell library trips shellcheck SC2034 — pass values in, don't share globals

When shared helpers move out of a program into a sourced `.sh` library, `shellcheck -S warning` reports SC2034 ("appears unused") on every variable the library sets but the sourcing program reads (and vice versa): the cross-file usage is invisible to shellcheck, so a previously clean file starts warning after a pure code move. The durable fix is to stop passing state through a shared global — take the value as a function argument instead (e.g. `_parse_common <subcommand> "$@"` rather than a global `$SUBCOMMAND`), which removes the warning structurally rather than suppressing it. For genuine library constants consumed only by callers, a file-level `# shellcheck disable=SC2034` with a comment is acceptable; avoid using the disable to blank a real finding. Verify with `shellcheck -S warning` on both files; note the repo's sourced-file convention (`# shellcheck source=...`, resolved cwd-relative) means SC1091 at default severity is pre-existing, not a regression.
