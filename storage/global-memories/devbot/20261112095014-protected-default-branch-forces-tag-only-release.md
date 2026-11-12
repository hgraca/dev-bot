---
date: 2026-11-12
keywords: ["devbot", "release", "tag-only", "branch-protection", "github"]
---

## A protected default branch forces the tag-only release path

When the default branch requires a pull request and status checks, `tag.sh push` refuses to move it. If every commit in the range is already merged and the local default equals the remote tip, the release is tag-only: `tag.sh plan --tag-only --version <v> --ref <sha> --notes-file <notes> --remotes <r>`, then `tag.sh tag --tag-only --ref <sha>`, `tag.sh push --tag-only`, and `release.sh release`. Tag the exact SHA the plan printed, never the branch ref. GET-E/dev-bot `main` is protected this way (PR + `lint`/`test` + one review); the 1.15.0 release used this path rather than pushing the branch.
