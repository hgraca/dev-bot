---
date: 2026-09-28
keywords: ["kafka", "kafkametricsreceiver", "consumer_group", "service.name", "signoz"]
trigger-on: ["signoz-alert-on-kafka-consumer-lag", "kafka-consumer-group-metrics"]
---

## kafkametricsreceiver consumer-group metrics carry no `service.name`

The OTel `kafkametricsreceiver` consumer-group series (`kafka.consumer_group.lag`, `.lag_sum`, `.members`, `.offset_sum`) arrive with **no `service.name` resource attribute**. Verified live against the SigNoz instance on 2026-09-28: the only resource keys on `kafka.consumer_group.lag_sum` are `deployment.environment`, `k8s.cluster.name`, `cloud.account.id`, `cloud.platform`, `cloud.provider`, `cloud.region` and `signoz.component`, and the consumer group / topic sit on the datapoint attributes `group` and `topic`. Two consequences for alerting: a rule on these metrics cannot group by `service.name` (the resulting group is empty), and any shared Slack channel title that brackets `{{ index .CommonLabels "service.name" | toUpper }}` renders an empty `[]` — it needs a fallback to `group`. Alert rules and templates built for application telemetry (which always has `service.name`) do not transfer to this family unedited.
