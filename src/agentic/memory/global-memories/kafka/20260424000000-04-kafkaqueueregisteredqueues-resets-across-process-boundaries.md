---
date: 2026-04-24
keywords: ["kafka"]
---

## KafkaQueue::$registeredQueues resets across process boundaries

`$registeredQueues` is an instance property on `KafkaQueue` that accumulates topic subscriptions across `pop()` calls. Each `artisan()` call in tests spawns a new PHP process, creating a fresh `KafkaQueue` instance. Any state accumulated in a previous process is lost. Multi-queue tests must use a single long-lived worker (`--max-jobs=N`) to let subscriptions accumulate.
