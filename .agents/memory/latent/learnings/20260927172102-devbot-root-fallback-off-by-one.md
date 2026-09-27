---
date: 2026-09-27
keywords: ["devbot", "DEV_BOT_ROOT", "shell", "path fallback", "sourced library"]
---

# `_shared/functions.sh` DEV_BOT_ROOT fallback was off by one

## The trap

`src/_shared/functions.sh` resolves its root as
`DEV_BOT_ROOT="${DEV_BOT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"`. The file is
`<repo>/src/_shared/functions.sh`, so `dirname` is `<repo>/src/_shared` and a single `/..` lands
on `<repo>/src` — not the repo root that every consumer appends to (`${DEV_BOT_ROOT}/src/...`,
`${DEV_BOT_ROOT}/.devbot.global.jsonc`). The bug stayed invisible because every entry point
(`bin/*.sh`, module lifecycle scripts) sets `DEV_BOT_ROOT` before sourcing, and the harness exports
it too — so even a manual test in the dev shell picks up the correct value and the fallback path
is never taken.

## The rule

Exercise the fallback with the variable unset: `env -u DEV_BOT_ROOT bash -c 'source
src/_shared/functions.sh; echo "$DEV_BOT_ROOT"'` must print the repository root (the parent of
`src/`). Any code that newly consumes `DEV_BOT_ROOT` from the shared library must be verified this
way, not in a shell that already exported it. The same `/..`-from-two-levels-deep error exists in
`src/tools/devbot-cli/update.sh:11` and `src/tools/litellm/update.sh:10`.
