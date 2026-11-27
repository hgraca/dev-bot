---
date: 2026-11-27
keywords: ["git", "gh-pr-view", "mergestatestatus", "isdraft", "mergeable"]
aliases: ["blocked is not unmergeable", "draft reads clean", "merge readiness"]
---

## `mergeable: MERGEABLE` is not "ready to merge", and `isDraft` is a separate field

`gh pr view --json mergeable` answers one question — would GitHub accept a merge of these trees — and no
others. A draft reports `MERGEABLE`; its state value is `CLEAN`, because GitHub's merge-state list does not
encode draftness there. `BLOCKED` is likewise not a defect: it is a missing approval, an unresolved
thread, or a requested change — all of them other people's gates, none of them CI.

So a gate that means "the checks are green" must read `isDraft` explicitly and must not wait on `BLOCKED`,
or it will hang forever on every pull request that is waiting for a reviewer. Exclude only the states that
mean the branch itself is not ready: `UNKNOWN` (not computed yet), `DIRTY`/`CONFLICTING` (conflict),
`BEHIND` (stale base), plus `isDraft`.

When reporting the outcome, print the merge state as well as the verdict. A gate that times out with only
"timed out" forces the caller to re-derive whether the branch was behind, conflicted or still computing —
three different actions collapsed into one message.
