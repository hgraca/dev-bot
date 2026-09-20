---
date: 2026-09-11
keywords: ["git", "autosquash", "fixup", "rebase", "sequence-editor"]
trigger-on: ["git-autosquash-shared-branch", "git-fixup"]
---

## Autosquashing your fixups on a branch another agent is also rewriting

On a branch shared with another active agent that has its own `fixup!` commits, a plain `git rebase --autosquash` folds **their** fixups into their targets too — never do that. Restrict the operation to your own fixups with a custom `GIT_SEQUENCE_EDITOR` that rewrites the todo: emit `pick <target>` followed by `fixup <your-fixup>` for each of your fixups, and re-emit every other commit as `pick` in its original position. Two traps bit hard: (1) git 2.55's interactive-rebase todo lines are `pick <sha> # <subject>` — the subject is prefixed with `# `, so a parser splitting `<cmd> <sha> <subject>` fails to match, and a "leave todo untouched on unexpected shape" guard silently turns the rebase into a no-op (the SHAs stay identical, which is how you notice). (2) If you build a `handled`/skip set containing a commit you never emit, that commit is **dropped** from the todo and `git rebase` deletes it — always emit every commit you set aside. Recover a dropped commit via `git reflog` + `git reset --hard <pre-rebase tip>` and redo; verify another agent's surviving commit by comparing its patch (`git show <old> --format=` vs `git show <new> --format=`), not the whole tree (a tree diff also shows the base changes your rebase introduced).
