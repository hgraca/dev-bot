---
date: 2026-11-27
keywords: ["git", "fixup", "autosquash", "rebase", "squash"]
aliases:
  [
    "rebuild commits from the final tree",
    "keep the commit split after a fold conflict",
  ]
---

## Rebuild a branch's commit split from its final tree when autosquash cannot fold

When fixups touch text introduced by a _later_ commit — a docs commit, say — autosquash moves them before
that commit and the fold conflicts, because the lines they edit do not exist yet at the target. Squashing
the whole branch into one commit is the usual answer, but sometimes the branch must keep its atomic split
(a tool change, then two docs commits that each own their tests).

The deterministic recovery keeps the exact tree that was reviewed, with no conflict resolution at all:

```bash
final=$(git rev-parse HEAD)                      # the reviewed tip
git reset --hard origin/main                     # clean base
git checkout "$final" -- <paths of commit 1>     # stage exactly that commit's files
git commit -m "<commit 1 message>"
# … repeat per commit, partitioning the changed paths
```

Partition the changed paths so each commit stages only its own files; the cumulative tree must equal
`git rev-parse "$final^{tree}"` afterwards. Two checks before pushing: `git log --oneline origin/main..HEAD`
shows the intended subjects with no `fixup!`, and `git rev-parse HEAD^{tree}` matches the pre-rebuild value.
A shared tree is the proof the review still applies.

If the base moved while the branch was open — someone else's merge landed — the trees differ by exactly
that movement. Confirm the branch's own files are unchanged with
`git diff --stat "$final" HEAD -- <your paths>`; an empty result means only the base advanced, which is
what you want.
