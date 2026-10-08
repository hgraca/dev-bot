---
date: 2026-10-08
keywords: ["release", "git", "git-tag", "gh-release"]
supersedes: ["ADRs/20260920132448-gated-release-command-script-owns-determinism.md"]
see: ["ADRs/20260920135609-release-merges-squash-fixups-before-tagging.md", "ADRs/20260922111500-release-version-scheme-major-zero-four-part.md"]
---

## Release tooling splits into `devbot:git-tag` and `devbot:gh-release`

The single `devbot:release` command and its six-subcommand `tools/release.sh` are replaced by two concerns, each with its own skill, tool and entry point:

- **git half** — the `devbot:git-tag` skill drives `tools/tag.sh` (`version`, `plan`, `merge`, `tag`, `push`).
- **GitHub half** — the `devbot:gh-release` skill and command drive `tools/release.sh` (`plan`, `release`).
- **shared plumbing** — both tools source `tools/git.sh`, a library that defines helpers only (default-branch resolution, remote slug and release capability, the version shape and bump, fixup folding, and shared flag parsing). It is not a `*.mcp.sh`, so it is not farmed into `.agents/tools/`.

Routing is by **skill description**, not a command. A request to "create a tag" loads `git-tag`; "make a release" loads `gh-release`. `gh-release` is the full-release entry point: it delegates the git half to `git-tag` (reusing `tag.sh`) and takes a **single** approval over a preview that concatenates the two tools' `plan` output, so a user asking for a release needs nothing else. The `devbot:release` command is retired.

Two properties are preserved deliberately. Each **tool plans exactly the steps it executes** — `tag.sh plan` describes only the git steps and `release.sh plan` only the release step — so no preview can promise a step its tool cannot run. And no VCS mutation precedes approval: `plan` reads `refs/remotes/origin/HEAD` rather than refreshing it, and only `merge` calls `git remote set-head --auto`. The helper stays a plain `.sh` — never a `*.mcp.sh` — so a mutating release tool is never globally callable by every agent.
