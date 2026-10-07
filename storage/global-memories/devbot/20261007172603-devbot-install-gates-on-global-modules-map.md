---
date: 2026-10-07
keywords: ["devbot", "install", "modules", "project-config"]
aliases: ["module enablement gate", "install skips project-only module", "machine-level module install"]
trigger-on: ["devbot-module-install"]
---

## `devbot install` skips modules enabled only in a project config

`devbot install` (`bin/install.sh`) and its module prereq pass (`_run_module_prereqs`) gate modules on the **global** `modules` map alone: `_install_modules` calls `_run_module_script` with no project dir, so `_devbot_get_disabled_modules ""` reads only `.devbot.global.jsonc` and treats every globally-`false` module as disabled. A module that is `false` globally but `true` in a project's `.devbot.project.jsonc` is therefore never installed — its `pre.sh` never runs and its `storage/<module>/skills` is never fetched — even though per-project `reinit` (which passes `PROJECT_DIR`, `bin/init.sh:535`) does register its MCP. The symptom is confusing: the MCP is wired and usable while the module's skills are absent and `.opencode/skills/<module>` is never symlinked. Workaround: run the module scripts directly — `bash src/agentic/<module>/install.sh`, then `bash src/agentic/<module>/init.sh <project>`. Proper fix: gate install/prereqs on "enabled for any registered project", not global-only.
