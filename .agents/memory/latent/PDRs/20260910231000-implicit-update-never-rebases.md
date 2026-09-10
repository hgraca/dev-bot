---
date: 2026-09-10
keywords: ["devbot", "update", "rebase", "release-tag", "auto-update"]
---

## Implicit `devbot update` never rebases a branch; only an explicit tag does

`devbot update` with no argument (and `devbot update --auto`, run by a bare `devbot` start) only moves a checkout that is at or behind the newest release tag. When HEAD is on a branch with commits of its own — classified `diverged` — the implicit path echoes "not a release checkout" and continues on the current version; it must never rebase, because an implicit update should not rewrite a branch. Only an explicit `devbot update <tag>` rebases the branch onto that tag (and on conflict aborts the rebase, restores state, and exits 1). This also keeps shallow installs safe: `install.sh` clones with `--depth 1`, whose truncated history can misclassify an ahead branch as diverged, so the implicit skip is the correct fallback.
