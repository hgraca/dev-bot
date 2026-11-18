---
date: 2026-11-18
keywords: ["shell", "set -u", "sourcing", "bash", "unbound variable"]
aliases: ["unbound variable", "DEV_BOT_ROOT", "source before default"]
trigger-on: ["bash-source", "set-u", "script-entrypoint"]
---

## `set -u` plus a variable used in a `source` path: default it first, and locate it by searching

A script that does `source "${ROOT}/lib.sh"` and only afterwards sets
`ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"` dies with `ROOT: unbound variable` whenever the
caller has not exported it — a clean shell, a CI job, or a test that sources a stripped copy of the
script. It survives in day-to-day use only because the realistic callers happen to export it, which
makes the ordering load-bearing by accident and hides the bug from everyone whose shell is configured.

Set the variable before the first read, and derive it by walking up from `$0` until a known marker
exists rather than assuming a fixed depth: the real layout puts a harness script three levels down, a
test harness plants the same script at the root of a fake install, and both have to resolve. When
nothing matches, fail with a message that names the variable and the fix — otherwise the next line
reports it as the unbound-variable error the change was meant to remove. Pin it with a test that runs
the script under `env -u <VAR>`, not with one that happens to inherit it.
