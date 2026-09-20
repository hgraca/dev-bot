---
date: 2026-09-11
keywords: ["mysql", "mysqld-exporter", "threads_created", "connections"]
trigger-on: ["mysql-connection-churn-metric"]
---

## mysqld-exporter's threads_created is flat under a healthy thread cache — use connections for churn

`mysql_global_status_threads_created` (MySQL `Threads_created`) only increments when MariaDB actually spawns a new OS thread. With a warm thread cache it barely moves — observed flat at 348 for 24h while the server handled ~11-16 new connections/sec. `rate()` of it is therefore 0, so any "thread creation rate" panel built on it is meaningless. Use the cumulative `mysql_global_status_connections` counter instead (monotonic, ~15/sec in the same window); `rate()` of it gives new connections/sec, which is the connection-churn signal (spikes = pool exhaustion / reconnect storms). `mysql_global_status_threads_cached` (~146-176) confirms the cache is doing its job.
