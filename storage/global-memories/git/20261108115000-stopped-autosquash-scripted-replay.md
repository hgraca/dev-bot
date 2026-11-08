---
date: 2026-11-08
keywords: ["git", "autosquash", "fixup", "rebase", "squash"]
aliases: ["autosquash stopped", "combination of commits message", "scripted fixup replay"]
---

## A stopped autosquash is finished with a scripted cherry-pick replay

`git rebase -i --autosquash origin/<default>` can stop mid-plan on a branch whose fixups were all
created by `git commit --fixup`: the working tree ends up carrying only the first group's changes, the
in-progress commit is titled `# This is a combination of N commits. # This is the 1st commit message:`,
and `git log origin/<default>..HEAD` shows a single commit with the earlier files deleted. An
explicit `GIT_SEQUENCE_EDITOR` does not change it; `git rebase --abort` restores the branch cleanly,
so abort first and never continue into that state. The deterministic replacement folds each
`fixup!`/`squash!`/`amend!` commit into its target without an editor: `git checkout --detach
origin/<default>`, then walk `git rev-list --reverse origin/<default>..<tip>` — `git cherry-pick -n
<c>` followed by `git commit --amend --no-edit` for a fixup subject, a plain `git cherry-pick <c>`
otherwise — and finally `git checkout -B <branch>`. Verify with `git diff <old-tip> HEAD`, which must
be empty, and check the commit count equals the number of non-fixup subjects.
