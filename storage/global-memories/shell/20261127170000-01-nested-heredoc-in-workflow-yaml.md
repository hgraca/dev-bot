---
date: 2026-11-27
keywords: ["shell", "heredoc", "github-actions", "bash-n", "yaml"]
aliases: ["workflow run block", "multi-line shell in YAML", "nested heredoc"]
trigger-on: ["github-actions-run-block", "shell-in-yaml"]
---

## A shell program inside a workflow `run:` block is read by nothing, and nested heredocs break on indentation

A `run: |` block is a YAML literal scalar: the common indentation of the block is stripped and every line keeps the rest. Author a line at 12 spaces where the block's base is 10 and the line arrives at the remote shell with two leading spaces — harmless for a command, fatal for a heredoc terminator, which then never matches and swallows the remainder of the script. The failure surfaces as a confusing `IndentationError` from the language whose heredoc was lost, or as `here-document delimited by end-of-file`.

Two rules follow. Put the program in a checked-in file (`bin/<task>`, `scripts/<task>`) and invoke it — then shellcheck, `bash -n` and a bats suite can read it, and the YAML shrinks to an invocation. And when a heredoc cannot be avoided, prefer a one-line `python3 -c` / `sh -c` over a nested `<<'EOF'`: the failure mode is silent and the diagnosis is slow.

Related trap in the same gate: `bash -n a.sh b.sh` parses **only** `a.sh`; the second path becomes a positional parameter and an invalid file passes. Syntax-check each file with its own invocation.
