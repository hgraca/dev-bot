---
date: 2026-11-13
keywords: ["shell", "bats", "set -e", "assertion", "grep"]
aliases: ["negated assertion", "refute grep", "test silently passes"]
---

## A `! grep` assertion in BATS never fails

BATS runs each test body under `set -e`, and **bash exempts a command whose status is inverted with `!` from `-e`** — so `! grep -q 'forbidden' file` returns non-zero, does not abort the test, and the assertion is inert. A test written to forbid a string silently passes whether or not the string is present.

Two ways to make it bite, both of which `-e` does honour:

```bash
# a plain test, not an inverted command
run grep -qF -- 'forbidden' "${FILE}"
[ "${status}" -ne 0 ]

# or capture and assert on the value
hits="$(grep -F -- 'forbidden' "${FILE}" || true)"
[ -z "${hits}" ]
```

The second form also survives `pipefail`. Do not rely on `! cmd | grep` or `! cmd && ...` either: only the inverted *pipeline* is exempt, and a trailing `|| true` re-arms the failure path.

Found while inverting three Copilot-request assertions in `devbot:gh-create-pr`'s bats suite: they had passed for months without ever asserting the thing they named.
