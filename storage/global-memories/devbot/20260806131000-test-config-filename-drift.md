---
date: 2026-08-06
keywords: ["devbot", "testing", "config"]
---

## Test config filename drift causes silent test failures

`up_compose_opts_tests.bats` had all 9 tests failing because the test setup created `.devbot.jsonc` but production `_docker_up()` expects `.devbot.global.jsonc` (renamed upstream, tests never updated). Secondary failures: compose files were at sandbox root (`docker-compose.litellm.yml`) but production auto-discovers from `src/tools/<name>/docker-compose.yml`. Tertiary: stub `functions.sh` was missing `_header_2`, `_header_3`, `_skip`, `_log`. All three root causes gave the same opaque error (`_header_2: command not found`) because the missing config file triggered `_error` before any compose logic ran. Fix: update test sandbox to match production config filename, directory structure, and stub completeness.
