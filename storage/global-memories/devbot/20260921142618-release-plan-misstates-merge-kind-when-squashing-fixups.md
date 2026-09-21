---
date: 2026-09-21
keywords: ["devbot", "release", "release.sh", "fixup-squash", "fast-forward"]
trigger-on: ["devbot-release", "release-plan-preview"]
---

## `release.sh plan` prints `Merge: merge commit` even when the merge will fast-forward

When a release branch carries `fixup!` commits, `release.sh merge` first runs a non-interactive `git rebase --autosquash` over the `origin/<default>..<source>` range, which replays the branch **onto the default branch**. By the time `git merge --no-edit <source>` runs, `<default>` is already an ancestor, so the merge is a **fast-forward**, not a merge commit. The plan's merge kind is computed earlier (`merge_kind="merge commit"` unless `git merge-base --is-ancestor "${base_ref}" HEAD`, release.sh around line 307), i.e. before that rebase — so it is wrong precisely in the case that matters: any release whose fixups will be squashed. Observed cutting 1.5.1: the approved plan said `Merge: merge commit`, and `main` came out linear with `feature/v1.5 == main` afterwards. The release outcome is still correct and no work is lost; only the preview lies, which matters because the plan is the human approval gate and the gated-release design promises the preview and the executed steps cannot drift. Fix by deriving the merge kind from the post-squash state (a non-zero fixup count implies the rebase, hence a fast-forward), or by dropping the line from the preview.
