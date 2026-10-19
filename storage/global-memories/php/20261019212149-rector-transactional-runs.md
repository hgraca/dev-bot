---
date: 2026-10-19
keywords: ["php", "rector", "rollback", "transactional", "refactor"]
aliases: ["rector partial apply", "multi-step rector", "rector snapshot rollback"]
---

## A multi-step Rector run needs a rollback snapshot

Rector runs one rule per invocation. An operation with a usages step followed by a declaration step can rewrite references and then fail; a plugin that also moves the file or rewrites the namespace makes the tree half-applied. Snapshot the source scope before the first apply step and restore it on every failure path.

Practical rules learned implementing the dev-bot PHP refactor plugin:

- Deduplicate overlapping roots to their shortest ancestors before snapshotting (`src/Sub` + `src` → `src`). Otherwise `cp -a src backup/src` after `backup/src/Sub` nests the snapshot and rollback creates `src/src/...`.
- Restore on: any step rc != 0 for `apply`, a namespace-rewrite or `mv` failure, an empty or malformed Rector document, and a document with `totals.errors > 0` even when the process exited 0.
- Validate every step document before relocating. A parser that `break`s on malformed JSON leaves `errors == 0` and lets the relocation proceed.
- Rector dry runs exit **2** when they find changes: accept 0 and 2 for `plan`, but require 0 for `apply`.
- The report must exit non-zero on `ok: false`; early `raise SystemExit` paths default to exit 0 unless given a status.
