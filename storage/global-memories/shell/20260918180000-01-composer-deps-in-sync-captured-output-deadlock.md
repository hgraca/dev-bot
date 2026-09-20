---
date: 2026-09-18
keywords: ["shell", "composer", "stdin", "deadlock", "make"]
trigger-on: ["composer-install-dry-run", "make-install-deps", "shell-output-capture"]
---

## Capturing a command's output into a shell variable hides its prompt and deadlocks the caller

A script of the form `OUTPUT=$(composer install --dry-run 2>&1)` that inherits a tty on stdin will block forever if the wrapped command decides to ask a question: the prompt is written into the captured pipe, so the user sees nothing while the process waits for an answer that can never arrive. Under `make` this presents as a silent hang after the last visible line, and stray Enter presses or retries do not clear it. Fix by passing `--no-interaction` (or the tool's non-interactive equivalent) so the command cannot prompt, and wrap in `timeout` so any residual stall fails visibly instead of wedging the caller. Also quote the variable when echoing it for diagnostics — unquoted `echo ${OUTPUT}` word-splits and glob-expands, so a literal `ext-opentelemetry *` in the captured text expands to the current directory listing.
