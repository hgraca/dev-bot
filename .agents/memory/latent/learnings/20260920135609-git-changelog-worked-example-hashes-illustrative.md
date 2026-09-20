---
date: 2026-09-20
keywords: ["git-changelog", "release", "changelog", "git"]
---

# git-changelog's worked example hashes are illustrative, not this repo's

`devbot:git-changelog`'s SKILL.md "Worked example — release v1.5" lists commit hashes and a 17-commit range that look like this repo's history but are fabricated — several of them (`797c8300`, `1197f056`, `52e37fc7`, `01a0cf15`, …) do not exist here; only the commit subjects resemble real ones. Trusting the example as ground truth for the v1.5 release suggested a 3-bullet changelog, while the real range `git log 1.4.0..HEAD` was 211 commits collapsing to ~17 bullets. Derive the range from the last tag, never from the example, and when a `release.v<M>-<N>.no-vcs.md` file already exists, re-audit the whole range with `git log` before editing it — the file's age is not a boundary, and its existing bullets can predate commits added after it was written (the v1.5 file here was missing the release command itself).
