---
date: 2026-09-02
keywords: ["shell", "python", "heredoc", "indentation", "embedded"]
trigger-on: ["bash-python-heredoc-indentation"]
---

## Python embedded in a bash function must be flush-left, or it raises IndentationError

When a `python3 -c "…"` block is written inside a bash function using the surrounding 4-space function indentation, Python sees the leading spaces on nested statements as an unexpected indent (`IndentationError: unexpected indent`) and exits non-zero — which silent guards like `2>/dev/null || true` swallow completely, leaving the bash variable empty and the caller failing for an invisible reason. Convention in dev-bot shell files: python bodies inside functions start at column 0 (see `_setup_external_module_storage` in `src/tools/external-modules/functions.sh`). Debug by running the generated script without the stderr redirect, or tracing with `bash -x` and executing the captured `python3 -c` body directly.
