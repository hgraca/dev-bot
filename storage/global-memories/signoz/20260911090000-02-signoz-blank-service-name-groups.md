---
date: 2026-09-11
keywords: ["signoz", "query-builder", "service.name", "group-by", "exists"]
trigger-on: ["signoz-query-builder", "signoz-alert-groupby"]
---

## Grouping a SigNoz query by `service.name` yields a blank group for series that lack it

Grouping metrics or logs by the `service.name` resource attribute produces an extra series whose label value is the empty string whenever a matching entity has no `service.name` — e.g. infra pods (opensearch, mongodb, redis) or CronJob pods that carry a pod label but no OTel service name. The blank group is easy to miss and, with a legend template like `{{service.name}}`, renders as the query name (e.g. `F1`) instead of a service. Exclude it with `service.name EXISTS` in the filter expression — `EXISTS` drops the empty-string group (verified live); otherwise its value is silently summed into the alert.
