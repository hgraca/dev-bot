---
date: 2026-11-26
keywords: ["shell", "pipeline", "exit-status", "tail", "pipefail"]
aliases: ["tail masks exit code", "make test | tail", "pipeline status lost"]
---

## Piping a command into `tail` reports `tail`'s status, not the command's

`make test 2>&1 | tail -40` exits 0 when the suite fails: the pipeline's status is the last command's, and `tail` succeeds at tailing. Nothing warns you — the output looks like a passing run truncated to its last lines, and only the absence of a failure line hints otherwise. `set -o pipefail` in the surrounding script would fix the pipeline but is not in effect in an agent's one-shot shell command, and it is not the whole answer either: `cmd | tail` with `pipefail` still discards the log you need to read after the fact.

Run the command with its output redirected, then print the status yourself — and read the file for detail instead of re-running:

```bash
{ make test > /tmp/out.log 2>&1; echo "EXIT=$?"; }   # status is the command's
grep -E '^(not ok|FAIL)' /tmp/out.log                # detail from the log
```

Same trap for `| grep`, `| head`, `| tee` in any agent command whose success must be known rather than eyeballed — redirect first whenever the exit code is the answer.
