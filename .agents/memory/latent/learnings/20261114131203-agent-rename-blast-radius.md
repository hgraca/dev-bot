---
date: 2026-11-14
keywords: ["agent-rename", "seed-once-config", "harness-init", "reconcile", "dev-bot"]
---

# Renaming an agent is a config migration, not a prose edit

## Seed-once configs are not rewritten

`opencode.jsonc` and `.claude/settings.json` are user-owned: `_write_jsonc_from_dist` treats an existing target as owned and skips it, so editing the dist template never reaches an existing project. A rename must ship an idempotent reconcile — `src/_shared/reconcile_agent_names.py` now rewrites `default_agent`, the `agent` map keys and claudecode's `agent` value, touching key/value positions only so a same-named model display elsewhere survives. Without it an upgraded project keeps a name no agent answers to: the default agent stops resolving (opencode falls back to `build`, then to a primary agent chosen by listing order) and every per-agent model override silently stops applying.

## Blast radius beyond prose

Three surfaces are easy to miss. Literals inside skills: the `make-plan` Per-Agent gate regex matched `PO` and went dead the moment artifacts started saying `po`. Artifact and tag names that embed the old spelling (`PO-DECISION-*.md`, `[DevBot-RememberSession]`, `[DevBot-AutoRecover]`): leave those, they are identifiers of a thing, not of the agent. Test fixtures: a case-insensitivity test that writes and reads the same casing becomes vacuous rather than failing, so keep the historical spelling on one side of the assertion. Grep for the literal, not only for the prose.

## Fresh worktrees lack runtime fixtures

`bin/tests/commands_tests.bats` needs `.devbot.global.jsonc` (copy it in, as CI seeds it) and `devbot list tools` needs the generated `.agents/tools` symlink farm, which a fresh worktree does not have. Two assertions fail there for environmental reasons; confirm the tool list in the main checkout before treating them as regressions.
