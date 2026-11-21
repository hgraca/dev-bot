---
date: 2026-11-19
keywords: ["shell", "bats", "grep", "test-guard", "vacuous"]
aliases: ["guard passes on a comment", "grep guard is satisfiable by prose"]
trigger-on: ["bats-guard-regex", "grep-based-test-contract"]
---

## A grep-based test guard must match a call, not a mention

A guard written as `grep -rq '_devbot_versions_env' <module>` passed for a module that never read its pin, because the token is a **prefix** of `_devbot_versions_env_seed` (a writer), appears in `docs.md` and `.bats` files, and — worst — can appear in the pinned file's own header. Four review rounds each defeated a successively tighter version: prefix match, suffix-scoped `--include` (filters file names, not executability), and a comment `# mention _devbot_versions_env_source "..."` that satisfied a "name followed by whitespace" pattern.

Bite only when the pattern is anchored to code: restrict to runtime files (`--exclude-dir=tests`; `--include` alone is not enough, and permission bits are not either because sourced files like `functions.sh` are not executable), strip comments per line (`sed -E 's/#.*$//'`), and require a call position (`^[[:space:]]*` or `\$\(` followed by the name and a space). Prove it by constructing the defeat — a module that only mentions the helper must fail the guard — before trusting it.
