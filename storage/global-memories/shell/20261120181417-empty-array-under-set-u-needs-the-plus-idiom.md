---
date: 2026-11-20
keywords: ["shell", "bash", "set-u", "arrays", "portability"]
aliases: ["unbound variable array", "bash 3.2 empty array", "macos bash array"]
trigger-on: ["bash-array-under-set-u"]
---

## `"${arr[@]}"` aborts a `set -u` script on bash < 4.4

A possibly-empty array expanded as `"${arr[@]}"` is an unbound-variable error under `set -u` before bash
4.4 — `arr[@]: unbound variable` — so a script that declares `local -a dirs=()` and iterates it dies
depending on whether anything populated it. macOS ships bash 3.2 as `/bin/bash`, so a script that works
on every Linux CI job and on the developer's Linux box can fail only on a Mac, and only on the path where
the array happens to be empty. The portable form is `${arr[@]+"${arr[@]}"}`: the `+` expansion yields
nothing at all when the array is unset or empty, and preserves each element — including elements
containing spaces — when it is not. Note that `set -u` does *not* protect you here: the error is exactly
what it raises. Guard only arrays that can be empty; a loop over a literal never-empty list is fine
unguarded, and guarding everything hides which ones actually matter.
