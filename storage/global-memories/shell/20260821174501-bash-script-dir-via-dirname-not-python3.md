---
date: 2026-08-21
keywords: ["shell", "bash", "SCRIPT_DIR", "python3"]
---

## Resolve a bash script's own directory with bash, not a python3 subprocess

Computing `SCRIPT_DIR="$(python3 -c 'import os,sys; print(os.path.dirname(os.path.realpath(sys.argv[1])))' "${BASH_SOURCE[0]}")"` breaks whenever `python3` is stubbed or absent: a test stub that echoes its arguments makes `SCRIPT_DIR` capture the literal `-c import os,sys…` string, so the follow-on `"${SCRIPT_DIR}/<script>.py"` path becomes garbage and the script fails with "file not found". Prefer bash-native resolution (`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, or `readlink -f` where GNU tooling is guaranteed) so the script is self-contained and immune to a stubbed interpreter. Observed in dev-bot at `src/agentic/memory/tools/search-memories/search-memories.sh:38` and `src/agentic/git/tools/git-report.sh:34` — the python3 stub used for arg-forwarding in `search-memories_tests.bats` turned `SCRIPT_DIR` into the echoed `-c` string, breaking all arg-forwarding tests.
