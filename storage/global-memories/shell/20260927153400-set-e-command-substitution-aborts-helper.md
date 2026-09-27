---
date: 2026-09-27
keywords: ["shell", "set -e", "command substitution", "pipefail", "redirect"]
trigger-on: ["bash-set-e-command-substitution", "shell-error-handling-in-helper"]
---

## A helper's unguarded command substitution aborts the CALLER under set -e

A helper that promises "never fails the caller" still aborts it when it runs an
unguarded command substitution under `set -e`. `_devbot_cap_file` did
`size="$(wc -c < "$file" | tr -d '[:space:]')"`; with `set -o pipefail` a failing
`wc` (unreadable file) makes the assignment non-zero, and `set -e` exits the
caller — here `opencode/start.sh`, aborting the harness launch. Guard the
substitution with `|| return 0` (and prefer a cheap `[[ -r "$file" ]]` first).

Separate trap: `2>/dev/null` on the command does NOT silence bash's own redirect
error for `< "$file"` — that error comes from the shell performing the redirect,
not from the command, so a `chmod 000` file still prints "Permission denied". An
upfront `[[ -r … ]]` guard removes the message as well as the abort.
