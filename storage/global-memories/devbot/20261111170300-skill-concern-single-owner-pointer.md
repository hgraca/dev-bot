---
date: 2026-11-11
keywords: ["devbot", "skill-authoring", "single-owner", "instructions"]
aliases: ["one owner per concern", "restating a rule across skills drifts"]
---

## Splitting a concern across skills: name one owner, point the rest at it

When a rule spans several skills — promotion of `thinking/` notes, their deletion, reconciliation of work artifacts — restating it in each file lets the copies drift and puts the reader in front of two contradictory instructions. A wrap-up change did exactly that: `reconcile-work` was told to "promote any lasting value first, then delete", while `remember-session` already claimed promotion and declared itself the last write to the memory vault. The agent then had two owners to choose between — the precise ambiguity the change existed to remove.

Make one skill the owner of each half of the concern and have the others say so and point at it: `devbot:remember-session` promotes, `devbot:reconcile-work` deletes, and `thinking` / `memory-management` describe the split without restating the procedure. A `MUST` in one file plus a paraphrased duplicate elsewhere is the failure mode, not a redundancy guard. Audit the whole surface of the concern, including commands and adjacent skills (`audit-memory`, `prune-memories`): the leftover that still deletes is what a reviewer finds next, and deleting is the half that loses data.
