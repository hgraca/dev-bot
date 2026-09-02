---
date: 2026-09-02
keywords: ["external-modules", "devbot", "architecture", "named-imports", "revert"]
supersedes: ["ADRs/20260902140000-external-modules-architecture.md"]
---

## External modules: revert to named imports, drop org/repo namespacing

**Status**: DECIDED 2026-09-02 (stakeholder), implemented in `715e19a6`.

### Decision

The external-modules machinery keeps the **named-import model**: config keys
are names (`addyosmani`, `mattpocock-grilling`, `mindrally-react`), wiring is
`.agents/<type>/<name>`, and the same git repo may be registered under several
names with no dedup guard — if two entries clone the same repo, so be it.

The org/repo namespaced identity, one-entry-per-repo dedup guard, provenance
prune, additive per-repo paths, per-path removal and the storage name
sanitizer (`/` → `__`) — built over two sessions (~24 commits) — are
**reverted** to the origin/main named-import state.

### Context

- Live config has two trivial single-repo entries. The namespacing + additive
  machinery existed to serve the disabled react/svelte `mindrally/skills`
  monorepo case (three collections under one repo) — a use case with no real
  user. Each layer (namespacing → dedup → provenance → per-path → union)
  only justified the one before it.
- The reverted work was entirely local and unpushed, so the revert is cheap
  and nothing external depends on it.

### Consequences

- Same repo under several names is intentionally tolerated; duplicate vendor
  clones/links cost is accepted.
- Naming-independent fixes that were kept: the `_devbot_get_disabled_modules`
  reader resolves `read_jsonc.py` beside the file (sandbox robustness).
- Memory records for the namespaced model (`ADRs/20260902140000-…`,
  `PDRs/20260902140000-…`, the implementation-gotchas file) are superseded;
  gotcha bullets 1-2 still apply to the restored merge script.
- Re-derive namespacing/one-repo-per-entry only when a real multi-collection
  repo is actually enabled and used.
