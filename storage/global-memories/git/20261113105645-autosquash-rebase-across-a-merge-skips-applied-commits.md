---
date: 2026-11-13
keywords: ["git", "rebase", "autosquash", "fixup", "merge"]
aliases: ["fold fixups after merging main", "rebase -i with a merge commit", "skipped cherry-pick"]
---

## Rebasing onto the default branch drops the merge and skips already-applied commits

A long-lived branch that merged `origin/main` mid-flight and then carries `fixup!` commits can still be folded with a plain `git rebase -i --autosquash origin/main` — no `--rebase-merges` needed. The merge commit disappears because its content is already in the new base, and the branch's own commits replay on top.

Two consequences to expect, and one to guard:

- **The tree changes even though the work did not.** After replaying onto a newer `origin/main`, `git diff <pre-rebase-tree> HEAD` shows the base branch's newer commits. Confirm the work is intact by diffing against the *base* instead (`git diff --stat origin/main..HEAD`) and checking the file count matches the pull request.
- **Already-applied commits are skipped** with `warning: skipped previously applied commit <sha>` (`--reapply-cherry-picks` overrides). This is correct when someone landed the same change on the default branch — for example a one-line formatting fix that unblocked CI got committed there by another session. Do not try to force it back in.
- **Capture the pre-rebase tree hash first** (`git rev-parse HEAD^{tree}`) so the comparison above is possible at all.

`GIT_SEQUENCE_EDITOR=: GIT_EDITOR=:` accepts the generated todo list without an editor, which is the only way an agent can run the interactive rebase; then hand the human a lease-pinned force-push:

```bash
git push --force-with-lease=refs/heads/<branch>:<old-remote-sha> origin HEAD:refs/heads/<branch>
```

The `<sha>:<branch>` lease form fails on git ≥ 2.45; the refspec form above works.
