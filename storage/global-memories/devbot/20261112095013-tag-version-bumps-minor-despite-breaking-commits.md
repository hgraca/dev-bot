---
date: 2026-11-12
keywords: ["devbot", "release", "semver", "tag.sh", "breaking-change"]
---

## `tag.sh version` bumps minor even when the range has breaking commits

`tag.sh version` resolves the next release by bumping the minor of the newest remote tag; it never inspects the commits. A range containing `!:` or `BREAKING CHANGE` commits still yields a minor bump (`1.14.0` → `1.15.0`), so semver correctness is the human's call: read the range with `git log --oneline <last-tag>..HEAD`, and pass `--version` to `tag.sh version`/`plan` when a major bump is wanted. In the 1.15.0 dev-bot release two `refactor(config)!:` commits shipped under a minor version by explicit user choice.
