---
date: 2026-11-15
keywords: ["shell", "pipefail", "set-e", "pipeline"]
aliases: ["grep returns 1 on empty input", "pipefail aborts caller", "set -e pipeline non-zero"]
trigger-on: ["shell-record-union-pipeline", "shell-pipefail-empty-input"]
---

## A pipeline that filters can exit 1 on empty input and kill a `set -euo pipefail` caller

A "record union" tail such as `{ printf …; [[ -f "$f" ]] && cat "$f"; } | sort -u | grep -v '^$' > out` returns **1** when there is nothing to keep: `grep` exits 1 on no matches, the `[[ ]] && cat` short-circuit returns 1, and `pipefail` propagates either. A library function called from a script running `set -euo pipefail` then aborts the caller — even though the function "succeeded". It surfaces only in production and only on the first run (when the record is still empty); unit tests that do not enable `set -e` stay green. Fix by writing the guarded form (`if [[ -f … ]]; then cat …; fi`), filtering with `sed` (always 0), and appending `|| true` to the pipeline when an empty result is legitimate. Same trap applies to `grep -q` under `pipefail` sending SIGPIPE upstream.
