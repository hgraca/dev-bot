---
date: 2026-11-04
keywords: ["shell", "set -e", "errexit", "bash function", "subshell"]
aliases: ["errexit suppression", "set -e ignored in if", "swallowed failure after refactor"]
trigger-on: ["bash-errexit-in-function-call", "shell-failure-propagation"]
---

## A function called from `if`/`&&`/`||` loses `set -e` for its whole body — and a subshell `set -e` does not restore it

Bash disables `errexit` for every command inside a function (or compound command) when the
function is invoked in a context where `-e` is already being ignored — the condition of
`if`/`while`/`until`, or any operand of `&&`/`||`. The suppression covers the entire call, so
a function that is the last statement of `foo || failed=1` can fail on every line and still
return 0 (a trailing `echo` wins). Replacing a child process (`bash script.sh`) with an
in-process function call therefore silently changes failure semantics: the child has its own
`set -e`; the function inherits the caller's ignored context.

Re-enabling errexit inside the function does **not** help: `set +e; ( set -e; f ); rc=$?;
set -e` still runs the rest of `f` when `f` is itself called under `if`/`||`, because the
ignored-context blanket applies to the whole call tree (verified on bash 5.2). The reliable
options are (a) keep the process boundary and pass an internal env flag that skips re-entry,
or (b) make the function detect and return its own failures explicitly.

Test with a genuinely failing child or body, not a stub that `return 1`s — a stub proves the
plumbing, not that the real failure aborts.
