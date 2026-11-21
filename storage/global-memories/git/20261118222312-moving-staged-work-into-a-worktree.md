---
date: 2026-11-18
keywords: ["git", "worktree", "staged", "patch", "dirty main checkout"]
aliases: ["move changes into a worktree", "git apply --index", "rescue staged work"]
trigger-on: ["worktree-dirty-main-checkout", "transfer-staged-changes"]
---

## Move staged work from a dirty main checkout into a new worktree with a patch

When the `worktrees` workflow applies but work was already started in the main checkout, `git switch -c` there is not the way out: the branch would live in the main checkout and its working tree mixes your hunks with unrelated uncommitted work. Move the change with a patch instead. Stage only your hunks (`git add -p`), save them (`git diff --cached > change.patch`), create the worktree from `origin/<default>`, and apply it there (`git -C <worktree> apply --index change.patch`). Back in the main checkout, reverse only your hunks (`git apply -R change.patch`) and clear the index (`git reset`): the reverse apply touches the regions in the patch and leaves unrelated hunks untouched, so the other agent's work survives. The branch then has the correct base and the pull request holds only your change. Check `git rev-parse HEAD origin/<default>` before relying on a patch taken relative to local `HEAD`: unpushed local commits can move the base, and files they changed will not apply cleanly.
