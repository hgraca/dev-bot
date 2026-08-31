---
date: 2026-04-24
keywords: ["kafka", "consumer"]
---

## M-TEST-004: Override workbench NOOP config in integration test setUp()

10 KafkaConnectorTest tests failed because `tests-workbench/laravel/config/queue.php` hard-codes `consumer_group_id => KafkaConsumer::NOOP`. The NOOP sentinel triggers a RuntimeException in `KafkaConsumer::consume()`, which is the intended behavior for non-Kafka environments.
When workbench config contains sentinel values that prevent real connections, override them in test `setUp()` via `Config::set()` _before_ resolving the queue connection. The connection is created once at resolution time — overriding config after `Queue::connection()` has no effect.
