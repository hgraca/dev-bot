---
date: 2026-10-29
keywords: ["shell", "process substitution", "set -e", "exit status", "ci gate"]
aliases: ["while read process substitution failure", "done < <(cmd) ignores exit status", "git log gate fails open"]
trigger-on: ["bash-process-substitution-gate"]
---

## A verdict computed inside a process substitution passes when the command fails

`while read …; do …; done < <(git log …)` keeps the loop in the current shell — an array filled inside it survives, which is why the form is popular for collecting matches — but it also discards the producer's exit status. A `git log` that dies on an unknown revision feeds zero lines, the body never runs, and the gate reports success. Nothing fires under `set -e`, because process substitution is asynchronous and its failure never becomes the loop's status. That is the exact inverse of command substitution, whose failure aborts the assignment.

Capture first and feed the loop from a here-string, so a failing producer aborts the script like any other failing command:

```bash
commits="$(git log --no-merges --format='%h%x1f%s' "origin/${BASE_REF}..HEAD")"
while IFS=$'\x1f' read -r sha subject; do …; done <<< "$commits"
```

An empty capture still yields one empty iteration, so keep the `[ -n "$sha" ] || continue` guard. Found in a GitHub Actions gate (`dev_tools-conventional_commits.yml`): the step printed "All commits on this branch are Conventional Commits" and exited 0 for a base ref it could not resolve. A gate whose input comes from a command must fail closed by construction, and its test must assert the failing-producer case — the happy path alone cannot tell a silent pass from a real one.
