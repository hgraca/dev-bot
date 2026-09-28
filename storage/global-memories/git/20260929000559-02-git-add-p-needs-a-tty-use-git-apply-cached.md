---
date: 2026-09-29
keywords: ["git", "add-p", "stdin", "partial-staging"]
trigger-on: ["git-partial-staging-script"]
---

## `git add -p` stages nothing when its answers arrive on a pipe

Piping hunk answers into `git add -p` (`printf 'nnny' | git add -p -- file`) leaves the index untouched in this environment: the hunk prompt wants a real tty, and the command still exits successfully with nothing staged, so the failure is silent unless you re-read `git diff --cached`. To split one file's changes across several commits non-interactively, extract the wanted hunks from `git diff` and apply them yourself — keep the diff header, concatenate only the chosen `@@` blocks into a patch file, then `git apply --cached <patch>`. That is deterministic and verifiable before committing, unlike hand-editing hunk headers in `-e` mode.
