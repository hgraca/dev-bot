---
date: 2026-09-16
keywords: ['git', 'rebase', 'autosquash', 'fixup', 'sequence-editor']
trigger-on: ['git-fold-commits', 'git-rebase-todo-rewrite']
---

## Folding plain commits onto their targets: rewrite the rebase todo, then verify by tree hash

`git rebase -i --autosquash` only reorders commits whose subjects are `fixup!`/`squash!`, so it is a silent no-op when the commits to fold carry real subjects (as happens when a project's policy forbids creating `--fixup` commits in the first place). Fold them anyway by scripting the todo: an `awk` script moves each commit's line to sit directly after its target and rewrites the verb from `pick` to `fixup`. Make that script fail loudly — track which targets actually received a fixup and `exit 1` if any did not, since git aborts the rebase when the sequence editor exits non-zero, whereas a silently dropped line would lose a commit. Dry-run first by capturing the todo with `GIT_SEQUENCE_EDITOR='cp "$1" /tmp/todo; false' git rebase -i <base>`, apply the transform to that copy, and diff the sha sets to prove nothing was added or dropped. A pure fold must not change content, so verify the tip **tree** hash (`git rev-parse HEAD^{tree}`) before and after the fold: if it matches, every check already run against the old tip still applies and no test re-run is needed. Expect conflicts when a folded commit's patch context includes symbols introduced by later commits — a fixup adding a test whose import block another commit later extended will conflict on the target; resolve by keeping only what is genuinely used at that point in history, because an unused import fails linting.
