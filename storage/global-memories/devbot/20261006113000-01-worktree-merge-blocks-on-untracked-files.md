---
date: 2026-10-06
keywords: ["devbot", "worktree", "git merge", "working tree", "untracked"]
aliases: ["worktree.sh merge", "working tree is not clean"]
trigger-on: ["devbot-worktree-merge"]
---

## `worktree.sh merge` refuses on any untracked file, including unrelated ones

`worktree.sh merge` gates on `[[ -z "$(git status --porcelain)" ]]`, so a single untracked file —
even an unrelated memory note the merge will not touch — aborts it with
`FATAL: merge: the working tree is not clean`. Because memory notes under `.agents/memory/**` are
routinely untracked until a memories commit lands, the merge is frequently blocked in an otherwise
healthy tree. This is the same failure class documented for `release.sh merge`
(`global/devbot/20261002102847-01-release-merge-blocks-on-dirty-tree-despite-noop.md`), via a
sibling tool with a different workaround.

Do not stash, commit, or discard the unrelated files to clear the gate. Instead replicate what the
tool does by hand, leaving them untouched:

```bash
git fetch origin
git merge --ff-only origin/<default>     # ensure local default == remote
git merge --no-edit <branch>
```

Then `worktree.sh remove <branch>` works normally (it refuses only uncommitted changes in the
worktree). Verify `git status --porcelain` still shows the original untracked entries afterwards.
