---
date: 2026-10-15
keywords: ["git", "autosquash", "rebase", "fixup", "force-push"]
aliases: ["autosquash rewrite boundary", "autosquash main preserves pushed commits", "rebase reuses unchanged picks"]
trigger-on: ["git-autosquash", "git-fixup-squash", "autosquash-base-choice"]
supersedes: ["git/20260910200502-autosquash-base-origin-branch-when-partially-pushed.md"]
---

## The autosquash rewrite boundary is the first fold, not the base

`git rebase -i --autosquash <base>` recreates only the commits from the first folded fixup onward. Every earlier pick is replayed onto its existing parent, so git reuses the original commit object and its SHA is unchanged — the base can be arbitrarily far below without touching them. Consequence for a partially-pushed branch: if every fixup targets a commit in the unpushed tail, basing on `main` (or the merge-base) rewrites only the unpushed commits; the already-pushed commits keep their ids and `git push` stays a fast-forward, with no force-push. A force-push is required only when a fold lands at or below an already-pushed commit, because that commit and everything above it then get new SHAs. Verified on a release branch of 81 commits, 49 already pushed, with all 8 fixups in the unpushed tail: basing the autosquash on `main` left all 49 published commits as ancestors of the new HEAD and the push needed no force. So the advice to base on `origin/<branch>` "to avoid rewriting pushed commits" is not required when the fixups are all unpushed (it remains the tighter, more defensive base). A minimal reproduction: commit base→P1→P2→P3 (treat P3 as the pushed tip)→U1→U2 plus a fixup! targeting U1; after `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <base>`, P1–P3 keep their SHAs while U1 and U2 are rewritten.
