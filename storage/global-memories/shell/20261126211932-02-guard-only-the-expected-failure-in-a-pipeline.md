---
date: 2026-11-26
keywords: ["shell", "pipefail", "set-e", "grep", "errexit"]
aliases:
  ["|| true hides errors", "pipefail grep no match", "expected non-zero status"]
---

## Guard only the expected failure, never the whole pipeline

A pipeline written `git for-each-ref ... | grep -vxF ... | sed ... || true` looks safe under `pipefail` and is not: `|| true` now swallows a failing `git` or `sed` too, so a broken ref enumeration is reported as "no matches" and the caller proceeds on a proof that never ran. Attach the guard to the value-producing command instead: capture the authoritative output with `refs="$(git for-each-ref ...)" || { echo "cannot enumerate refs"; exit 1; }`, then filter it with `siblings="$(printf '%s\n' "$refs" | grep -vxF ... || true)"` where a no-match genuinely is the normal case. The same trap applies to a deliberately-failing command, such as a rebase preview whose sequence editor exits non-zero to abort untouched: `|| true` cannot distinguish that expected failure from a pre-editor failure (dirty tree, rebase already in progress, lock error), so capture its stdout and require the expected artefact — `plan="$(GIT_SEQUENCE_EDITOR='grep -v "^#" "$1"; false' git rebase -i --autosquash <base>)"` then fail if `$plan` is empty or if the command actually succeeded.
