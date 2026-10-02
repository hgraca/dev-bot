---
date: 2026-10-02
keywords: ["agent instructions", "git commits", "shared working tree", "concurrent agents"]
see: ["PDRs/20260821225210-universal-agent-safety-rules.md"]
---

## Committing agents assume a shared working tree and commit only their own changes

Devbot, developer and teamlead — the three agents that make commits — each carry an inline `MUST`
rule: assume other agents and humans may be editing the same checkout on the same branch, and treat
changes they did not make as normal rather than a bug. They stage and commit only their own changes
with `git add <specific-files>` (never `git add -A` or `git add .`), never stage, stash, discard or
revert another's uncommitted work, and surface a block instead of resolving it. The rule is scoped
to a shared checkout; an isolated linked worktree is exempt, since the per-task `worktrees` default
already isolates those trees.

The rule deliberately overrides `devbot:optimize-instructions`' anti-duplication convention (writing
rule #4: keep one canonical location, reference from others) by inlining the same text in three role
files. Rationale: enforcement must sit where the commit decision is made — an agent reaches the
commit step from its own role file, not from a skill it may not have loaded — so the presence
guarantee outweighs the duplication. The canonical one-liner already in `devbot:git-atomic-commits`
is left untouched; it stays correct in every context, while the role-file rule adds the shared-tree
framing the concurrent-agent scenario needs.
