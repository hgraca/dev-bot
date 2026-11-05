---
date: 2026-11-05
keywords: ["kafka", "msk", "security-patching", "broker-restart"]
aliases: ["monthly broker reboot", "MSK maintenance window", "broker connection refused"]
trigger-on: ["kafka-broker-connectivity", "msk-maintenance"]
---

## MSK patches its brokers monthly, one at a time, and clients see connection refused

AWS MSK runs a `SECURITY_PATCHING` operation roughly monthly (observed: the 4th, starting ~18:00-19:00 UTC, lasting 2-2.5h) that restarts each broker in turn. Clients see `Connect to ipv4#<broker>:9094 failed: Connection refused` and `SSL handshake failed: Disconnected: connecting to a PLAINTEXT broker listener?` from librdkafka, plus `[Kafka producer] Unable to flush, messages might be lost. Error: 'Local: Timed out'` from producers whose 10s flush lands on the broker being patched. Prove it from the cluster operation, not the metrics: `kafka:ListClusterOperations` (paginate — `MaxResults: 20` can hide the recent entry behind older ones) returns `OperationType: SECURITY_PATCHING` with creation/end times matching the incident. CloudWatch corroborates per broker: `ConnectionCount` collapses to ~2 while `CpuIdle` dips to ~18-24%, then both recover; `BurstBalance` stays ~99 (so it is not burst-credit exhaustion) and `ActiveControllerCount` stays 1 (not a controller election). `kafka:DescribeClusterOperation` returns an empty `OperationSteps` for security patching, so the operation record is the whole story. Design clients to tolerate losing one broker — retry — and never fail a committed write because the publish timed out.
