---
date: 2026-11-16
keywords: ["kafka", "msk", "replication-factor", "kafka-reassign-partitions", "UpdateTopic"]
aliases: ["increase RF", "RF 2 to 3", "replica assignment"]
trigger-on: ["kafka-replication-factor-change", "msk-topic-reassignment"]
---

## MSK replication factor cannot be raised by UpdateTopic or by --generate

Neither supported API changes an existing topic's replication factor. `kafka:UpdateTopic` accepts only `Configs` (base64 properties) and `PartitionCount` — there is no RF parameter at all, and `ReplicationFactor` is a read-only field on `DescribeTopic`/`ListTopics`. Worse, `kafka-reassign-partitions.sh --generate --broker-list "1,2,3"` **preserves the current RF** and only rebalances across the listed brokers: run against an RF=2 topic it emits a perfectly plausible two-replica proposal that reshuffles leadership on every partition while leaving RF unchanged — it looks like a plan and fixes nothing. The reliable method is to hand-build the target from the *current* assignment and append the one broker each partition is missing, keeping the existing replicas in order so the leader (first entry) never changes; that adds a follower to every partition with zero leadership churn. Execute with `--throttle` (bytes/sec, ~half the broker's baseline network) and poll `--verify` until every partition reports completed — the throttle is applied to all brokers and only `--verify` clears it. A dropped client does not interrupt the reassignment (it runs controller-side) but it does leave that cluster-wide throttle in place, so always finish the verify loop, and save the `Current partition replica assignment` block that `--execute` prints as the rollback file.
