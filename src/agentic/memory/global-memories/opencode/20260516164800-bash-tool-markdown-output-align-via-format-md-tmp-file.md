---
date: 2026-05-16
keywords: ["opencode", "tool", "bash", "format-md", "markdown", "tmp-file"]
---

## Align markdown table output from bash scripts via format-md.py + tmp file

When a bash tool script produces markdown table output, align columns by:

1. Redirecting python/script output to a `mktemp` file instead of stdout
2. Running `python3 format-md.py <tmpfile>` (in-place edit)
3. `cat`-ing the tmp file to stdout
4. Cleaning up with `trap 'rm -f "${TMP_OUT}"' EXIT`

```bash
TMP_OUT="$(mktemp /tmp/my-tool-XXXXXX)"
trap 'rm -f "${TMP_OUT}"' EXIT
python3 - ... > "${TMP_OUT}" <<'PYEOF'
# ... output markdown to stdout ...
PYEOF
if [[ "${FORMAT}" == "markdown" && -f "${FMT_SCRIPT}" ]]; then
  python3 "${FMT_SCRIPT}" "${TMP_OUT}" >/dev/null 2>&1
fi
cat "${TMP_OUT}"
```

`FMT_SCRIPT` resolved as: `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/../format-md/format-md.py`

The TS tool wrapper does the same: write stdout to `os.tmpdir()` file, run `format-md.py` on it, read back, delete.

**Key**: always capture to tmp first — heredoc stdout cannot be piped and formatted in one pass without re-running the expensive search.

Reference: `ripgrep-report` (commit `daf1918`). Cross-ref [[20260515000000-01-wrapping-a-system-cli-tool-as-an-opencode-tool-ts]].
