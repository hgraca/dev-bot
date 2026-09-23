---
date: 2026-09-23
keywords: ["git-commits", "skills", "preemptive", "commit-body"]
see: ["ADRs/20260823111100-software-development-hub-skill-annexes.md"]
---

## Commit craft is consolidated into one always-loaded `devbot:git-commits` skill

The rules shared by the git technique skills now live once, in a new always-loaded `devbot:git-commits` skill: the message skeleton `<type>(<scope>)!: <description>`, the subject rules, the **Problems/Solutions body format** (bullets ≤72 chars, the why and not the how — the diff already shows the how), the why-belongs-in-the-body-not-in-code-comments rule, the history-rewrite safety check, and a routing table that replaces the four per-skill `## Related skills` blocks. `git-conventional-commits` keeps the type taxonomy and points at `git-commits` for the skeleton; `git-atomic-commits` keeps grouping/ordering/branch-creation/migrations; `fixup` and `advanced-operations` keep their workflows and point at the shared safety rule. The preemptive set became `git-commits` + `git-conventional-commits` + `git-atomic-commits` + `git-fixup-commits`: `git-advanced-operations` was **removed** from every preemptive manifest because a session is not guaranteed to need history surgery, so it is loaded on demand via the routing table. `software-development` §Commit Protocol deliberately keeps pointing at the individual skills rather than the new core. Cross-references to the moved content had to be rewired outside the git module too (`devbot.md` pointed at `git-conventional-commits` for the commit-body format). Rationale: four copies of the same rule drift apart, and the one unrecoverable mistake (rewriting shared history) was warned about in only two of them.
