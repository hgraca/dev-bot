---
date: 2026-10-02
keywords: ["php", "dev-tools", "dependabot", "composer-plugin", "template"]
aliases: ["get-e/dev-tools dependabot bootstrap", "Deps commit prefix", "dependabot.yml not re-synced"]
trigger-on: ["dev-tools-dependabot-template"]
---

## The GET-E dev-tools dependabot.yml template is copy-once, not synced

`get-e/dev-tools` bootstraps `.github/dependabot.yml` from `src/GitHub/dependabot.yml` **only when the file does not already exist** (`Plugin.php` for PHP projects, gated by `composer.json` `extra["GET-E/dev-tools"]["dependabot"]`; `plugin.sh` for non-PHP, gated by `dependabot=true` in `dev-tools.sh`). Unlike the `dev_tools-*.yml` workflows, which are rewritten unconditionally on every composer run, the dependabot config is copied once and then locally owned — a template change does **not** propagate to existing projects, and a pre-existing hand-written file wins the copy guard. So standardising a dependabot setting (e.g. `commit-message.prefix` `"Deps"` → `"chore(deps)"`) is a two-part job: edit the template **and** edit every existing `.github/dependabot.yml` individually (12 existed under `~/Development/Get-e/`; `platform` had no `commit-message` block, `positioning-flights-api` was fully commented out). Note also that `dev-tools.ai` is a stale second clone of the same `GET-E/dev-tools` remote, not a distinct project.
