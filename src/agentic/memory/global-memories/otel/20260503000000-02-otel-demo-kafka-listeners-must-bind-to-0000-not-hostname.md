---
date: 2026-05-03
keywords: ["otel"]
---

## OTel Demo Kafka: listeners must bind to 0.0.0.0, not hostname

Kafka in KRaft mode fails with "Address not available" if `KAFKA_LISTENERS` uses the service hostname (e.g., `kafka:9092`). The pod's network interface isn't bound to that name at startup. `KAFKA_CONTROLLER_QUORUM_VOTERS` must use `localhost` for single-node KRaft.
Fix: `KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093` and `KAFKA_CONTROLLER_QUORUM_VOTERS=1@localhost:9093`.
