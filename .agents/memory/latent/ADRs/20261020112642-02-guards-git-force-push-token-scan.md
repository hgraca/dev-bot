---
date: 2026-10-20
keywords: ["devbot", "guards", "force-push", "shell", "regex"]
aliases: ["guard token scan", "inline alias guard", "force-push guard"]
---

## Git force-push and inline-alias guards are token scans, not regexes

`src/agentic/guards/tools/guards.ts` tokenizes each command segment into shell words (quotes removed, escapes resolved, spaces inside a value sentinel-encoded) and applies two deterministic checks to a git invocation, including `env git …` and nested runner bodies: a force-push is an exact `push` word followed by `-f`, `--force`, `--force-with-lease` or `--force-with-lease=…`, and any `-c alias.NAME=…` / `-calias.NAME=…` global option before the subcommand is blocked outright because alias values may be shell bodies (`! …`) or use Git config quoting. The dist configs now carry only the `rm -rf`, `sudo` and `qmd` regex rules; the git checks are built in. This replaced a regex that parsed Git options and shell quoting, which produced a stream of bypasses (quoted `-C`, attached values, ANSI-C quoting, inline aliases) and catastrophic backtracking on repeated tokens while running synchronously on every tool call. A token scan is linear and quoting-agnostic; unmodelled shell syntax (`$(…)`, backticks, `$'…'`) falls back to a fail-closed text check for `push` plus a force flag rather than being treated as safe.
