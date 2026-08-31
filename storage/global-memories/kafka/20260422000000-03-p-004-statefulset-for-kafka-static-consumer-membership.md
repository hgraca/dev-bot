---
date: 2026-04-22
keywords: ["kafka", "consumer"]
---

## P-004: StatefulSet for Kafka static consumer membership

- **Pattern**: Event-bus workers that consume from Kafka use `StatefulSet` (not Deployment) with `KAFKA_GROUP_INSTANCE_ID` set to `metadata.name` via Downward API. Each StatefulSet needs a matching headless Service (`clusterIP: None`). Use `updateStrategy.rollingUpdate.maxUnavailable: 1` for terminate-then-start rollout. Set `terminationGracePeriodSeconds` higher than `queue.connections.kafka.consumer_timeout_ms`.
- **When**: Creating any new Kafka consumer worker deployment.
