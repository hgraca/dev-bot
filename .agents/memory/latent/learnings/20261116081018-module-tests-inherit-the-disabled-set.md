---
date: 2026-11-16
keywords: ["devbot", "bats", "devbot_global_config", "disabled-set", "hermetic"]
aliases: ["module test inherits the machine disabled set", "codebase-index skipped in test", "DEV_BOT_GLOBAL_CONFIG fixture"]
---

# A module test that calls the apply step inherits the machine's disabled set

Once `_devbot_apply_runtime_mcps` started honouring module enablement, tests that exercise it silently depended on the developer's (and CI's) global config. CI seeds `.devbot.global.dist.jsonc`, which disables `aws`, `sentry`, `jetbrains` and more, so a group named `aws-demo` was skipped there and the suite went red only in CI; locally the same tests passed because this machine enables aws. The same trap hit the jetbrains suite (its module is disabled in this machine's config) and the codebase-index wrapper test (the engine pair selects `codebase-memory`).

Fix: point `DEV_BOT_GLOBAL_CONFIG` at a purpose-built fixture for the test — `{}` when the test is about the pipeline, or the exact provider/module map when it is about enablement (`{"codebase_index_provider": "codebase-index"}`). `_devbot_global_config` honours that variable, so no `DEV_BOT_ROOT` gymnastics are needed. Corollary: when a suite is green locally and red in CI, diff the *config* the two environments seed before suspecting the code.
