---
date: 2026-11-04
keywords: ["devbot init", "scaffold test", "graphifyignore", "module enablement", "bats"]
aliases: ["devbot_tests.bats", "graphify module disabled"]
---

# The init scaffold test must gate module artefacts on module enablement

`src/tools/devbot-cli/tests/devbot_tests.bats` uses the developer's real `.devbot.global.jsonc`
(copied to a temp path) to seed `devbot init`. Its `.graphifyignore` assertion was guarded only on
`command -v graphify`, so it failed on any machine where the graphify CLI is installed but the module
is disabled — a legitimate configuration, and the shape of this machine's config. The file is absent
because `_run_module_script` never runs a disabled module's `init.sh`.

## The rule

An assertion about an artefact a module generates must gate on that module being enabled for the
project as well as on its external dependency being present. Derive enablement from
`_devbot_get_disabled_modules <project>` (honours global + project config, and the mutually exclusive
provider pairs) rather than reading the global config directly, so a project-level override is not
missed. `graphify_disabled()` in that test file is the reference.
