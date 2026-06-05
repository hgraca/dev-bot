---
date: 2026-04-24
keywords: ["kafka", "consumer"]
---

## Workbench config hard-codes consumer_group_id to NOOP

`tests-workbench/laravel/config/queue.php` sets `consumer_group_id => KafkaConsumer::NOOP`. This is intentional — it prevents real Kafka connections when running non-Kafka tests. But it means **every integration test** that resolves `Queue::connection('kafka')` must call `Config::set('queue.connections.kafka.consumer_group_id', 'message-bus-test')` in `setUp()` _before_ resolving the connection. Config overrides after connection resolution have no effect.
