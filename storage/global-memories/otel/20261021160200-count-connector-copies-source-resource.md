---
date: 2026-10-21
keywords: ["otel", "count-connector", "cardinality", "transform", "logs"]
aliases: ["log count metric", "count connector series churn", "keep_keys resource"]
---

## The count connector stamps the source resource onto every count

Counting logs with the OTel `count` connector inherits the input logs' full resource, so each count carries pod uid, node, image digest and every other resource attribute — 190 series for ~15 services, plus a fresh set on every deploy, and the alert filters cannot group by deployment without also carrying all of it. Reduce it to the dimensions you alert on with a `transform` processor on the connector's metrics pipeline (`metric_statements: - context: resource / statements: - keep_keys(attributes, ["service.name", "deployment.environment"])`). The connector's own `attributes:` list sets **datapoint** attributes and is unaffected by the resource strip, so the requested dimensions survive while the churn does not; verify the result in ClickHouse rather than assuming, because pre-existing series keep their old label sets until they age out.
