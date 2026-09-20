---
date: 2026-09-20
keywords: ["devbot", "memory-vault", "git-info-exclude", "global-memories"]
---

## A machine-local exclude can silently hide the global memory store

`storage/global-memories/**` — the shipped, tracked global knowledge base reached through the `latent/global/<tech>/` symlink — can be listed in `.git/info/exclude`. Because that file is machine-local and itself untracked, nothing announces the rule: `git check-ignore` is the only way to see it, and the notes committed before it keep working, so the store looks healthy while every new note quietly stays untracked. A three-week, 132-note backlog accrued in this repo that way, and the only visible symptom was untracked entries in `git status`, which read as noise rather than as missing knowledge. Before assuming a vault note is committed, run `git check-ignore <note>`; and after such a rule is removed, expect a large one-off backlog to surface at once.
