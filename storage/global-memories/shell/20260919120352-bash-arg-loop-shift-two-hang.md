---
date: 2026-09-19
keywords: ["shell", "bash", "argument-parsing", "shift", "infinite-loop"]
trigger-on: ["shell-while-arg-parsing-loop"]
---

## `shift 2` with one argument left spins a `while [[ $# -gt 0 ]]` parser forever

A `while [[ $# -gt 0 ]]; do case "$1" in --file) FILE="${2:-}"; shift 2 ;; esac; done` loop hangs permanently when the flag is the last argument: `shift 2` fails (only one positional remains), leaves `$1` and `$#` unchanged, and the loop re-parses the same flag forever — full CPU, no output, ended only by the caller's timeout (reproduced: `timeout 3 script --file` exits 124). Never assume a two-token shift succeeds; guard it: `--file) FILE="${2:-}"; if (( $# >= 2 )); then shift 2; else shift; fi ;;`. The trap is reachable from any caller that forwards user- or agent-supplied arguments (an MCP tool arg list, for example), so it is not limited to hand-typed commands.
