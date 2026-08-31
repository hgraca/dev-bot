---
date: 2026-08-25
keywords: ['mysql', 'mariadb', 'performance_schema', 'digest', 'prepared-statements']
trigger-on: ['perf-schema-digest', 'events_statements_summary_by_digest', 'empty-transactions', 'prepared-statements-invisible']
---

## MariaDB performance_schema digest hides binary-protocol prepared statements — "empty transaction" readings are often artifacts

`events_statements_summary_by_digest` (and `log:['query']`) capture only **text-protocol (COM_QUERY)**
statements. Statements executed via prepared statements (COM_STMT_PREPARE/EXECUTE — how Prisma and most ORMs
send queries) are **invisible to the digest**. Observed on driver-service (2026-08-25): a DB that appeared to
run "97.6% empty BEGIN/COMMIT with no real queries" for weeks was actually processing a full write workload —
the BEGIN/COMMIT (sent as text by the adapter) and driver probes showed up in the digest, while the app's
prepared INSERTs/SELECTs never did. Before concluding "empty transactions / idle DB", verify with a
**driver-level statement logger** (e.g. the mariadb npm driver's `logger.query`, which logs Prepare/Execute with
full SQL) — the only view that shows binary-protocol statements. Related InnoDB insight from the same
investigation: per-COMMIT duration at `innodb_flush_log_at_trx_commit=1` is the fsync of the **instance-wide**
redo buffer; isolated commits (group-commit leaders) pay ~5–20ms while batched commits (followers) cost
microseconds — so commit cost differences across schemas/apps on one RDS reflect commit batching, not
transaction content.
