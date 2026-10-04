---
date: 2026-10-04
keywords: ["git", "commit.gpgsign", "gpg", "test", "ci"]
aliases: ["gpg failed to sign the data", "pinentry in tests", "signing prompts in tests"]
---

## Disable git signing in test suites

A developer's global `commit.gpgsign = true` (and `tag.gpgSign`) leaks into any test that
creates a throwaway repo and commits: each `git commit` invokes gpg, which is slow, can
prompt pinentry to unlock the key, and fails outright under load (`gpg: signing failed:
Cannot allocate memory`) — failing tests for reasons unrelated to the code. A per-repo
`git config commit.gpgsign false` in each fixture works but is easy to miss; the robust
fix is suite-level config injection:

```sh
GIT_CONFIG_COUNT=2 \
GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
GIT_CONFIG_KEY_1=tag.gpgSign GIT_CONFIG_VALUE_1=false \
bats -r src/ bin/
```

`GIT_CONFIG_*` (Git ≥ 2.31) injects config at `-c` precedence, so it overrides the
global setting for every git subprocess the suite spawns — no per-test edits and no key
prompt. Put it on the test runner (Makefile/CI), never in the developer's own config.
