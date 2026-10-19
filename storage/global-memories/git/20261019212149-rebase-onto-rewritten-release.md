---
date: 2026-10-19
keywords: ["git", "rebase", "onto", "release-branch", "rewritten-history"]
aliases: ["rebase release branch changed upstream", "replay old base commits"]
---

## Rebasing onto a rewritten release branch needs `--onto`

When a shared release branch is rebased or force-updated while a feature branch is open, the feature branch's old base is no longer an ancestor. `git rebase release/v1.9` then computes the range from the merge base and replays every old base commit, conflicting on unrelated files.

Abort and replay only your own commits:

```bash
git rebase --onto release/v1.9 <old-base>
```

Verify with `git log --oneline release/v1.9..HEAD` (your commits only) and `git merge-base --is-ancestor <old-base> release/v1.9` (false). Do **not** rebase the shared release branch itself in a checkout carrying other agents' uncommitted work.
