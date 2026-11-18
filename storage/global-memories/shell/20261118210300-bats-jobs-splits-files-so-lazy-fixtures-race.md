---
date: 2026-11-18
keywords: ["shell", "bats", "parallel", "fixture", "flaky"]
aliases: ["bats fixture race", "within-file parallelism", "lazy per-file fixture"]
---

## `bats --jobs N` also splits a file unless you pass `--no-parallelize-within-files`

BATS parallelises at file granularity only when told to: with `--jobs N` and no `--no-parallelize-within-files`, tests _inside_ a file can run concurrently on separate jobs. A lazy per-file fixture — "build this tree on first use, share it with the later tests" — then races: two tests both see `[[ ! -d dir ]]`, both build into it, and one reads a half-written tree while the other is still assembling it. The failures land on _unrelated_ tests (whatever ran second), report the fixture's own error, and vanish when the file runs alone, which reads as flakiness rather than as a race.

Two defences, both cheap: always pass `--no-parallelize-within-files` when a file shares fixtures across tests, and make the builder record its result even when it fails — under `set -e` (which BATS uses) a failing builder aborts the test before any status file is written, so the next test cannot tell a broken build from a good one and asserts against garbage. Write the status unconditionally with `{ build …; } || rc=$?; printf '%s' "$rc" > status`.

A claim-directory lock (`mkdir` on a sibling path, losers wait for the status) makes the helper safe either way, but it serialises the losers and is slower than the flag; use it only when the runner cannot be controlled.
