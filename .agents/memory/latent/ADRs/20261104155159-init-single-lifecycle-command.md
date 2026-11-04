---
date: 2026-11-04
keywords: ["devbot", "init", "reinit", "lifecycle", "detection"]
aliases: ["single lifecycle command", "init reinit unification", "already initialised detection"]
---

## `devbot init` is the single lifecycle command; `reinit` is an alias

`devbot init` owns both lifecycle branches: a project without `.devbot.project.jsonc` is
wired directly, and a project that carries it runs the reset path first (module `reset.sh`
scripts, wipe of `memory/active/modules`, pre-modules memory cleanup) before wiring.
`devbot reinit` is a pure alias that execs `bin/init.sh`, so it auto-detects too — including
the bare-start auto-reinit. `init --all` replaced `reinit --all`, applying detection per
registered project, and `init` gained `--full` and `--help`.

Detection deliberately uses the project config, not `.devbot.project.sha`: the baseline is
cleared at the start of every run and is absent after an interrupted one, so it would make a
crash read as "never initialised" and skip the reset path. The wiring runs through a child
process (`DEV_BOT_WIRING_ONLY=1 bash bin/init.sh <dir>`) because a function called under
`if`/`||` loses `errexit` for its whole body; the env flag skips detection so the child
cannot recurse into the reset path. A bare `devbot` in a non-initialised folder refuses to
start with a "run devbot init" error instead of printing help.
