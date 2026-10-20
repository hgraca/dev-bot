---
date: 2026-10-16
keywords: ["devbot", "guards", "git", "force-push"]
aliases: ["guard regex", "git -C push", "force push prohibited"]
trigger-on: ["devbot-guard-rule"]
---

## Match git force-pushes by tokens, not by a literal regex

A guard rule written as `"regex": "git push --force"` is fragile: it misses `git -C <path> push --force` (options before the subcommand) and blocks prose that merely mentions the phrase. Widening the regex to parse Git's option grammar then creates two more problems: shell quoting (`"-C"`, quoted values, backticks) and catastrophic backtracking on repeated tokens.

`guards.ts` therefore tokenizes the command (`shellWords` — quotes removed, escapes resolved, spaces inside a value sentinel-encoded) and scans the words:

- an exact `push` word followed by `-f`, `--force` or `--force-with-lease` is a force-push, regardless of Git options, quoting, `$`/backtick expansions, or a runner wrapper (`env git …`, `bash -c "git …"`).
- quoted prose is one token, so `git commit -m "… push --force"` and `git log --grep="push --force"` do not trip it.
- any inline `-c alias.NAME=…` / `-calias.NAME=…` global option before the subcommand is blocked outright: alias values may be shell bodies or use Git config quoting, and Git aliases cannot shadow built-ins, so resolving a hidden force-push is not worth the risk. `git grep -c alias.publish` is a read-only search and is not blocked.

The dist configs keep only the `rm -rf`, `sudo` and `qmd` regex rules; the git checks are deterministic token scans, so they cannot be bypassed by re-quoting or stalled by backtracking. Run the command directly instead of hiding it behind an alias, and treat a guard hit as "reword or ask the human" — never as "rephrase the command to slip past the pattern".
