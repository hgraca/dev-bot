---
date: 2026-10-01
keywords: ["refactor", "rename", "notice", "feedback"]
---

## A refactor rename reports a notice, it does not fail

When a rename resolves to nothing the refactor tool must explain why, not return a bare
`ok` with `0 file(s)`. A fully-qualified `--class` is kept verbatim — never substituted
with a same-short-named class — and a bare one is resolved to its FQCN; when the class
cannot be resolved, or nothing matched, the response carries a `notice` and the process
still exits 0. The stakeholder decision was explicit: an unresolved symbol is feedback,
not a failure — exiting non-zero on a legitimate "already renamed" re-plan would break
the tool's own idempotence and its post-apply self-verification. Notices are attached
only when the run changed nothing (no `files`, no `file_move`), so a successful run is
never accompanied by a misleading explanation. On an apply, occurrences the engine left
outside quoted strings (a doc-block `@see Old::method()`) are reported as
`unrewritten_references`.
