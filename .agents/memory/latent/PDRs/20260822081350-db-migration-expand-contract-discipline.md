---
date: 2026-08-22
keywords: ["devbot", "migrations", "expand-contract", "bc-break"]
---

## DB migrations ship in their own atomic commit via expand/migrate/contract

Database migrations must ship in their own atomic commit/PR, never bundled with the code that depends on them, and never introduce a backward-incompatible (BC) schema break. A task with a migration ships in 2–3 commits/PRs: expand (an additive migration so old and new code both work), migrate (the new code), contract (a follow-up cleanup migration once the old code is retired). Never drop/rename in place, and never bundle a destructive migration with an additive one. Rationale: merging to the default branch auto-deploys, so each commit/PR is a production deploy — a destructive schema change in the same commit as the code that uses it breaks the running code during the rollout window. The rule is encoded in the `developer` and `devbot` agents (MUST bullets), and in the `architecture-rules` and `git-atomic-commits` skills; the schema mechanics live in the `deprecation-and-migration` skill.
