---
date: 2026-05-06
keywords: ["opencode"]
---

## Single canonical JSONC parser via `load_jsonc`

Every Python heredoc that reads a `.jsonc` file imports the canonical helper instead of inlining its own regex/tokenizer:

```bash
python3 - "${FUNCTIONS_PATH}" "${file}" "${key}" <<'PYEOF'
import json, sys
sys.path.insert(0, sys.argv[1])
from strip_jsonc import load_jsonc

with open(sys.argv[2]) as f:
    data = load_jsonc(f.read())
PYEOF
```

`load_jsonc` (in `src/functions/strip_jsonc.py`) handles `//`, `/* */`, string literals, trailing commas, AND missing commas. The shell side passes `${FUNCTIONS_PATH}` (or derives it from `BASH_SOURCE`) so the heredoc can `sys.path.insert` it. When to apply: any time you need to read a JSONC file from a shell script. Never copy-paste an inline `strip()` regex — see [[gotchas]] "opencode.dist.jsonc contains // comments". Established by sweep in commit `da21176` after `make init` crashed on a `//` comment in `.devbot.jsonc`.
