---
date: 2026-09-25
keywords: ["otel", "kafka", "kafkametrics", "receiver"]
trigger-on: ["otel-kafkametrics-receiver"]
---

## `kafkametrics` receiver: version-specific config keys, and metrics it does not emit

At collector-contrib 0.139.0 the component key is `kafkametrics` (the snake_case `kafka_metrics` rename came later), the required list is `scrapers` (not `metrics`), the topic filter is the regex `topic_match` — whose default `^[^_].*$` already excludes internal topics — and the interval is `collection_interval` (not `scrape_interval`). SASL `AWS_MSK_IAM_OAUTHBEARER` is supported if the broker needs it. Which metrics exist depends on the scrape level: `brokers` gives `kafka.brokers`; `consumers` gives `kafka.consumer_group.*` including lag; only `topics` gives `kafka.topic.partitions` and `kafka.partition.{current_offset,oldest_offset,replicas,replicas_in_sync}`. At this version it emits **none** of `kafka.topic.replication_factor`, `kafka.topic.min_insync_replicas`, `kafka.topic.log_retention_period/size`, `kafka.partition.count`, `kafka.partition.offline` or `kafka.partition.underReplicated` — so any dashboard or alert written against those stays empty permanently, not merely until data arrives. Always read the receiver's README **at the deployed tag** rather than from `main`: field names and available metrics both moved across versions, and the mistake is silent.
