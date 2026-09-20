---
date: 2026-09-20
keywords: ["git", "ls-remote", "annotated-tag", "tag-sorting"]
trigger-on: ["git-ls-remote-tags", "git-remote-tag-lookup"]
---

## `git ls-remote --tags` returns a peeled `^{}` ref for every annotated tag

`git ls-remote --tags <remote>` lists annotated tags twice — `refs/tags/1.5.0` and a peeled `refs/tags/1.5.0^{}` — so code that derives a tag _name_ from that output must filter the `^{}` entries with `grep -v '\^{}$'`, or the newest-tag lookup returns `1.5.0^{}` and a derived version becomes `1.5.0^{}.1.0`. The bug is invisible until the first _annotated_ tag is pushed (lightweight tags have no peeled ref), which is typically the first real release, so it survives testing that only uses lightweight tags. For version ordering use `git ls-remote --tags --sort=-v:refname <remote>` (git ≥ 2.18) rather than GNU-only `sort -V`.
