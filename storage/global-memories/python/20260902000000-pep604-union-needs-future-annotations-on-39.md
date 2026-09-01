---
date: 2026-09-02
keywords: ["python", "pep604", "annotations", "macos", "future"]
trigger-on: ["python39-compat", "pep604-union"]
---

## PEP 604 union annotations (str | None) crash on Python 3.9 — add from **future** import annotations

PEP 604 `X | None` in function signatures is evaluated eagerly at import time
(no `from __future__ import annotations`), requiring Python >= 3.10. macOS
ships `/usr/bin/python3` = 3.9.6 by default, so any Python tool using
`str | None` / `list[str] | None` crashes on import with
`TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'` — every
invocation fails, including via MCP tools. Note `list[str]`/`dict[str,str]`
(PEP 585) alone are fine on 3.9; it is only the `|` unions that break. Fix:
add `from __future__ import annotations` as the first import (after the module
docstring) in every flagged file — defers annotation evaluation to strings,
restoring 3.7+ compat with zero behavior change. Also assert the python floor
at install: macOS users need `brew install python` (3.10+) or the future
import. Regression-test structurally (assert the future import precedes any
def) since a 3.9 interpreter may not be available on the dev box.
