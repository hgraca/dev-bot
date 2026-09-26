---
date: 2026-09-26
keywords: ["devbot", "review", "reviewer", "aws", "datasources"]
---

# Two @reviewer passes over the aws/datasources rework, and the coverage gap that remains

`release/v1.6` gained 31 commits on top of the cherry-picked `dc4b1acf` ("Add AWS module"): the `aws` module reworked onto a connections model (11 commits) and the `datasources` sidecar class for OpenSearch/S3 (7), each followed by its review fixes (8 and 5).

## What was reviewed

Two passes, both delegated to `code-reviewer` with an explicit range plus the intent and acceptance criteria from the plan:

- `dc4b1acf..80b7583b` (the 11 `aws` commits) → REQUEST CHANGES: 1 BLOCKER (literal credentials handed to a resolver on argv) + 6 WARNING + nits.
- `b44b0295^..9f68f1e0` (the 7 `datasources` commits) → REQUEST CHANGES: 1 BLOCKER (an advertised size cap nothing read) + 10 WARNING + nits.

Every finding was addressed as its own commit, per `devbot:address-review`. Both BLOCKERs were real and reachable through each module's own documented configuration. The highest-value output was the blast-radius cluster — a broken sidecar build aborting the whole `docker compose up` — which the design's own justification (sidecars are isolated because they are separate containers) had assumed away.

## What was not

- The **13 fix commits** were never re-reviewed; the stakeholder accepted them on the full suite being green. That is where a regression *introduced by* an address would live — two were caught mid-fix (a `re.sub` callback with no capture group, and a `pkill -f` that killed its own shell).
- `dc4b1acf` itself, as the base of the first range, was never reviewed; only the files it leaves untouched (`external-modules.json`, `pre.sh`, `update.sh`, `functions.sh`) survive from it.

A later audit should read "31 commits, reviewed" as **18 reviewed + 13 unreviewed fixes**, not full coverage.
