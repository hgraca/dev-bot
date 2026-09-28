---
date: 2026-09-28
keywords: ["kafka", "msk", "consumer-lag", "kafkametricsreceiver"]
trigger-on: ["msk-consumer-lag", "msk-canary-exclusion"]
---

## Reading MSK consumer lag: `group` vs `groupId`, and where the canary actually appears

MSK exposes consumer lag through two exporters that name the same thing differently: the OTel `kafkametricsreceiver` labels it `group`, while MSK's JMX exporter (`kafka_consumer_group_ConsumerLagMetrics_Value` on `:11001`) labels it `groupId`. Filtering the JMX metric by `group` does not error — it returns a single empty-bucket series, so the mistake reads as "no data" rather than "wrong key"; check the field keys first. MSK's own canary groups (`amazon.msk.canary.group.broker-*`, on the internal topic `__amazon_msk_canary`) are **not uniformly present**: measured on two clusters they appear on the receiver's `kafka.consumer_group.members` but on none of `lag_sum`, `lag` or `offset_sum`. So a canary filter applied only where lag is read still leaves the canary visibly listed on a members panel, and a filter on a metric that never carries it is harmless — but it is not evidence that the canary is handled. Exclude by prefix (`group NOT LIKE 'amazon.msk.canary.group.%'`) so the filter survives a broker replacement. Finally, `list-nodes` returns **broker nodes only** — no controller endpoints, even on KRaft — so a DNS-service-discovery target list is brokers-only by necessity.
