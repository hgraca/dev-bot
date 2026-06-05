---
date: 2026-04-24
keywords: ["kafka"]
---

## M-TEST-003: Use --max-jobs=N instead of multiple --once calls for multi-queue integration tests

Multi-queue Kafka integration test initially used two separate `artisan('queue:work', '--once')` calls — one per queue. Each `artisan()` spawns a new PHP process, resetting `KafkaQueue::$registeredQueues`. The second queue was never subscribed.
When testing multi-queue consumption where topic accumulation depends on in-process state (`$registeredQueues`), use a single long-lived worker with `--max-jobs=N` instead of separate `--once` invocations. Separate processes reset all static/instance state.
