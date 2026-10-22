---
date: 2026-10-22
keywords: ["shell", "exec", "stderr", "redirection"]
aliases: ["exec 2>/dev/null", "shell-wide stderr", "silenced fd close"]
trigger-on: ["shell-exec-redirection", "bash-fd-close"]
---

## `exec` with only redirections applies them to the whole shell

`exec 210>"file" 2>/dev/null` does not scope the redirects to the fd it names: with no command, bash
applies **every** redirection to the current shell, so the `2>/dev/null` meant to hide a failed fd
open silences stderr for the rest of the process. In dev-bot this closed the session-registry lock
before `bin/up.sh` ran, so every error after it — compose's own failures, module up-script output,
the startup error itself — went to /dev/null; a failed start tore the containers down and printed
nothing about why. The same trap applies to `exec 200>&- 2>/dev/null`.

Group the redirect so it cannot outlive the statement: `{ exec 210>"file"; } 2>/dev/null` — the
group's redirect ends with the group, while the fd change persists. Distinguish this from a subshell,
which is already scoped and legitimate: `(exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null`.

Detect it with an anchored search for the ungrouped form —
`^[[:space:]]*exec [0-9]+[<>][^;]*2>[[:space:]]*/dev/null` — and prove the fix by checking
`ls -l /proc/$$/fd`: a surviving `2 -> /dev/null` is the bug.
