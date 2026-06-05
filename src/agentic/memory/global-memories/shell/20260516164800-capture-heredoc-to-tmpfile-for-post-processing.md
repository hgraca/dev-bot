---
date: 2026-05-16
keywords: ["bash", "stdout", "post-process", "tmpfile", "format"]
---

## Capture bash heredoc output to tmpfile for post-processing

When a bash script uses a Python heredoc to produce output that needs post-processing
(e.g. table formatting), the heredoc cannot be piped directly — it prints to stdout
before the post-processor runs. Solution: redirect heredoc output to a tmpfile, run
the post-processor on the file in-place, then `cat` the result.

```bash
TMP_OUT="$(mktemp /tmp/my-tool-XXXXXX)"
trap 'rm -f "${TMP_OUT}"' EXIT

python3 - "${ARGS[@]}" > "${TMP_OUT}" <<'PYEOF'
# ... python logic ...
PYEOF

# Post-process in-place, then emit
python3 "${POST_PROCESSOR}" "${TMP_OUT}" >/dev/null 2>&1
cat "${TMP_OUT}"
```

The `trap ... EXIT` ensures cleanup even on error. The post-processor (e.g. `format-md.py`)
modifies the file in-place; `cat` then sends it to stdout for the caller.

Reference: `ripgrep-report.sh` (commit `daf1918`). Cross-ref [[20260515000000-01-wrapping-a-system-cli-tool-as-an-opencode-tool-ts]].
