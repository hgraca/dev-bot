---
date: 2026-09-23
keywords: ["git", "rebase", "patch-id", "verification"]
trigger-on: ["base-moved-rebase", "verify-rebase-content", "patch-id-check"]
---

## A base-moved rebase changes a kept commit's patch-id even when its content is preserved — prove preservation with a context-stripped line diff

When a rebase moves a branch's base — `git rebase --onto main <last-redundant-sha>` after the upstream advanced, or any replay whose upstream moved — a kept commit's `git patch-id --stable` changes even though its diff is semantically identical, because the surrounding context lines and hunk headers differ. The commonly-quoted proof "confirm the kept commit's patch-id is unchanged" is therefore invalid after a base move and raises a false "content was lost" alarm: on `fix/db-optimizations-03-customer-role-checks` the geo commit's patch-id stayed byte-identical while the memberships commit's changed (`37a762190…` → `05b7851b2…`) purely because its base moved. `git diff <pre-rewrite-ref> HEAD` cannot help either, since the base moved too (it reports the whole upstream delta). The reliable check strips context from both patches and diffs only the changed lines: `git show <old-sha> | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)'` against the same for `<new-sha>` — an empty diff proves the added/removed lines are identical, i.e. the conflict resolution preserved intent. Pair it with `git diff --stat <old-parent>..<old-tip>` versus `git diff --stat main..HEAD` to confirm the same file set and line counts, and `git diff --check` to rule out leftover conflict markers.
