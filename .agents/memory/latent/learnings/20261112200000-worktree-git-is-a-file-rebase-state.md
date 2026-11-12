---
date: 2026-11-12
keywords: ["worktree", "git", "rebase", "worktree.sh", "rebase-merge"]
---

# A linked worktree's .git is a file — rebase-state probes must go through git

In a linked worktree `.git` is a **file** pointing at `<common>/worktrees/<name>`, so
`test -d .git/rebase-merge` is always false there even while a rebase is stopped on a
conflict. During ARC-1016 a failing `git rebase -i --autosquash` left HEAD detached
mid-rebase; the probe said "no rebase", `git log` showed only the commits already
replayed, and it looked like two commits had been dropped.

## Reliable probe

```bash
git rev-parse --git-path rebase-merge   # -> <common>/worktrees/<name>/rebase-merge
git status --short --branch             # "## HEAD (no branch)" + UU/DU lines
```

`git status` alone is enough: a detached HEAD with unmerged paths means the rebase
is still in progress.

## Recovery that worked

1. `git rebase --abort`
2. `git reset --hard <pushed head>` — the push is the only trustworthy record
3. Re-create the fixup commits, splitting them **by target commit** (a fixup that
   touches files belonging to two different targets conflicts when autosquash
   replays it after the first)

## Second trap in the same session

`git rebase --autosquash origin/main` after `origin/main` has advanced pulls the new
upstream commits in, so the squashed tree no longer matches the tree CI validated.
To keep a pre-merge squash tree-identical, replay onto the branch's **original base**
(`git rebase --onto <old-base> origin/main`) and verify with
`git diff <pushed-head> HEAD` — it must be empty.
