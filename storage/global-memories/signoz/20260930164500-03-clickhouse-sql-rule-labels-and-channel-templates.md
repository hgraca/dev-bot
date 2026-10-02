---
date: 2026-09-30
keywords: ["signoz", "alert-labels", "notification-template", "clickhouse-sql", "channel-title"]
trigger-on: ["signoz-alert-channel-template", "signoz-alert-labels"]
---

## A `clickhouse_sql` alert rule's labels are only its SELECT columns, so channel templates can render an empty bracket

A SigNoz alert's labels (the `CommonLabels` a Slack/webhook template interpolates) come from the
columns the query returns — for a `clickhouse_sql` query, exactly the `SELECT` expressions, with the
`GROUP BY` dimensions becoming the labels. A `builder_query` rule gets labels from its `groupBy`
fields instead. So a rule whose query does not return a given field has **no** such label, and a
channel template that references it renders an empty segment rather than failing.

Concretely: a log-growth rule written as `clickhouse_sql` selects `ts, service.name,
deployment.environment, value` and has no `severity_text` column. Routing it to a channel whose
title brackets `.CommonLabels "severity_text"` produced `[PROD][SERVICE][] <alertname>` — the
severity bracket empty because the label is absent (this is the same class as a template taking
`.CommonLabels.job` for a rule that carries no `job`). A `builder_query` rule grouped by
`severity_text` renders the bracket fine, which is why the fault appears only when rules from
different query types share one channel.

Fix idiom: guard the bracket so it disappears when the label is absent —

    {{ with index .CommonLabels "severity_text" }}[{{ . | toUpper }}]{{ end }}

Diagnose it by comparing the rule's query columns/`groupBy` against every `.CommonLabels.<x>` the
channel title and text reference; a label the query cannot produce is the empty segment.
