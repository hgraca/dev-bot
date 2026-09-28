---
date: 2026-09-28
keywords: ["kafka", "consumer-group", "rdkafka", "opentelemetry"]
trigger-on: ["kafka-consumer-span", "messaging-kafka-consumer-group"]
---

## A Kafka span's consumer group must come from the consumer that joined, not from a queue config key

A consumer span is attributed to a group by `messaging.kafka.consumer.group`, and the tempting source is the framework's queue config (in Laravel, `queue.connections.kafka.consumer_group_id`). That key belongs to the Kafka **queue driver**. An application that builds its own `RdKafka\KafkaConsumer` — a service provider doing `$conf->set('group.id', …)` — joins a different group, and one application routinely runs several consumers with several different groups, so no single config key can describe them. Reading the queue key yields a span that names a group nobody joins, and the tests stay green because they assert the same wrong key. Pass the group into the span helper from each call site, or read exactly the key the consumer constructor reads. Verify against live data rather than the config: the group names under `kafka.consumer_group.members` are the ones actually joined, and a queue-driver key showing up there with real members means two consumers are running side by side.
