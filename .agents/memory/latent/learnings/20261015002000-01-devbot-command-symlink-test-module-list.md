---
date: 2026-10-15
keywords: ["devbot", "command", "devbot-cli", "bats", "init-scaffold"]
---

# A new module command must be added to the init-scaffold test's module list

`src/tools/devbot-cli/tests/devbot_tests.bats` asserts that each module's commands are symlinked into `.opencode/commands/devbot/` — but it iterates a **hand-maintained** `MODULES_WITH_COMMANDS` array, not a glob over `src/agentic/*/commands`. A module that is not in that list (e.g. `devbot`, which gained `work-autonomously`) has its command symlink go unasserted: the test stays green even if the wiring silently breaks.

## What to do

When you add a command to a module, add the module name to `MODULES_WITH_COMMANDS` in the same change, then rebuild the farm with `bash src/tools/devbot-cli/init.sh <project>` and confirm the symlink exists under `<devbot_dir>/commands/devbot/`.

This is the test-side companion to the "Adding a command to a dev-bot module takes three things, not one" learning (file + `docs.md` manifest + farm rebuild) — the array is a fourth, easily forgotten step.
