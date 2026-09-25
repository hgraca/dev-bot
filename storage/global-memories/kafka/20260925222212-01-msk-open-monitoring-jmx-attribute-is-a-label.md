---
date: 2026-09-25
keywords: ["kafka", "msk", "jmx", "open-monitoring"]
trigger-on: ["msk-open-monitoring"]
---

## MSK Open Monitoring carries the JMX attribute in a `name` label, not the metric name

MSK's managed jmx_exporter (port 11001, `/metrics`, plaintext; the node exporter is 11002) exposes every MBean attribute as a family named `kafka_<package>_<MBean>_<derived>` with the attribute in a **label**: `kafka_controller_KafkaController_Value{name="OfflinePartitionsCount"}`. Grepping the metric _names_ for `OfflinePartitionsCount` therefore finds nothing and wrongly concludes the signal is absent — select on the label instead. `kafka_server_ReplicaManager_Value` carries `UnderReplicatedPartitions`, `UnderMinIsrPartitionCount`, `OfflineReplicaCount`, `ReassigningPartitions` and `LeaderCount` the same way, and consumer lag is `kafka_consumer_group_ConsumerLagMetrics_Value` with `name` in `OffsetLag` / `MaxOffsetLag` / `EstimatedTimeLag`, per groupId, topic **and partition**, at no extra cost. There is **no retention metric at all** — Kafka retention is a topic config, not an MBean — so `kafka.topic.log_retention_*` can never be sourced from JMX. MSK also publishes its own canary (`amazon.msk.canary.group.*` on the `__amazon_msk_canary` topic) which every panel and alert must exclude. Two operational notes: a workstation normally has no route into the VPC, so verify from inside the cluster rather than from a laptop; and cluster-scoped values such as `OfflinePartitionsCount` are reported identically by every broker, so aggregating them with `sum` triples the number — use `max`, or group per cluster rather than per broker.
