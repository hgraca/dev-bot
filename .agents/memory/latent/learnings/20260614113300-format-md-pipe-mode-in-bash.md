---
date: 2026-06-14
keywords: ["devbot", "format-md", "pipe", "bash", "markdown"]
---

# format-md.py pipe mode for bash scripts

The `src/agentic/format-md/tools/format-md.py` script supports pipe mode: when called with no arguments and stdin is not a tty, it reads stdin and writes formatted markdown (with aligned table columns) to stdout. This lets bash scripts format markdown tables inline without writing temp files: `echo "${table_content}" | python3 .../format-md.py`. Used in `bin/agentic-tools.sh` to align the output markdown table before display. The script accumulates table lines in a variable, pipes through format-md.py, then echoes the formatted result. Only table lines are piped — non-table output (`_header_1`, `_ok`, etc.) remains outside.
