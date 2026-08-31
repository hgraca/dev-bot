---
date: 2026-08-20
keywords: ["mysql", "performance_schema", "mariadb", "rds"]
trigger-on: ["performance-schema", "mariadb-performance-schema"]
---

## performance_schema engine is startup-only; only consumers/instruments are runtime-tunable

`performance_schema` (the engine) is a read-only startup variable on both MySQL and MariaDB — you cannot `SET GLOBAL performance_schema=ON`. On AWS RDS it is a **static** parameter, so flipping it requires a reboot. Database Insights (Performance Insights) auto-manages it (parameter group shows `0` while the running instance is `ON`, confirmed only via `SHOW GLOBAL VARIABLES`), but enabling Database Insights on an instance where it is already OFF will NOT turn it on without a reboot. In contrast, the digest/instrumentation toggles are runtime-only and need no restart: `UPDATE performance_schema.setup_consumers SET ENABLED='YES' WHERE NAME='statements_digest'` and `UPDATE performance_schema.setup_instruments SET ENABLED='YES', TIMED='YES'`. MariaDB 10.5+ defaults `performance_schema` to ON. Changes to `setup_consumers` reset on restart unless persisted via the parameter group.
