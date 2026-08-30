---
name: devbot:audit-fix
description: Grab an audit report (produced by devbot:audit slash command) and address the flagged issues.
---

The slash command devbot:audit has been run, inspect the latest audit report and address any issues found.

You can find the report under `tests/test-project/<devbot_dir>/memory/thinking/devbot-audit-NN.md`,
where `NN` is the next sequential integer starting at `01`.
List the existing `devbot-audit-*.md` files in that directory to find the last one.

If no report can be found under `tests/test-project/<devbot_dir>/memory/thinking/devbot-audit-NN.md`, then
try within the project root path itself `<devbot_dir>/memory/thinking/devbot-audit-NN.md`.

The label `<devbot_dir>` is the config `devbot_dir`, set in `.devbot.project.jsonc:devbot_dir`
or `.devbot.global.jsonc:devbot_dir`, which is `.agents` by default.
