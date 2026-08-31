---
date: 2026-08-22
keywords: ["git", "gpgsign", "commit", "test", "hermetic"]
trigger-on: ["git-commit-gpgsign"]
---

## global commit.gpgsign leaks into test repos and slows commit-based tests

A developer's global `commit.gpgsign=true` (with `user.signingkey`) makes every `git commit` in a temp test repo trigger a GPG-agent round-trip (~1.3s each). A bats suite that `git init`s and commits in `setup()` for 17 tests ran 47s instead of ~18s, all from GPG signing. Bats/shell tests that create repos and commit must be hermetic: run `git -C "$REPO" config commit.gpgsign false` (or pass `-c commit.gpgsign=false`) after `git init` so global config doesn't leak in. Symptom to recognize: the individual git commands profile fast (ms each) but the test file is slow — check global git config (`git config --global --list`) before blaming the tool under test.
