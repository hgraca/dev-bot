---
date: 2026-11-25
keywords: ["shell", "bash", "test-mock", "parameter-expansion"]
aliases: ["mock-empty-vs-unset", "colon-dash-swallows-empty"]
---

## A bash mock needs `${VAR+set}`, not `${VAR:-default}`, to tell empty from unset

`${VAR:-default}` substitutes the default when `VAR` is **unset OR empty**, so a test that exports `VAR=""` to model "the tool printed nothing and failed" silently gets `default` instead — and the assertion then covers the opposite case from the one it claims. In a docker-mock, `echo "${MOCK_RUNNING:-true}"` turned a test asserting "no recreate when the container state is unreadable" into a second copy of "no recreate when the container is running": the test passed with and without the behaviour it was written to protect, and only a reviewer reading the mock noticed. Distinguish the two states explicitly — `${VAR+set}` expands to `set` only when `VAR` is set, including when empty, so `[[ -n "${VAR+set}" && -z "${VAR}" ]]` is the "set but empty" branch — and use `${VAR-default}` (no colon) when only *unset* should take the default. The trap is worth watching for in any mock whose knob has three states, not two.
