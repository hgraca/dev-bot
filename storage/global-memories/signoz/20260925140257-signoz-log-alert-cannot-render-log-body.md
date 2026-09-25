---
date: 2026-09-25
keywords: ["signoz", "alerts", "notifications", "logs"]
trigger-on: ["signoz-log-alert", "alert-notification-template"]
---

## A SigNoz log-based alert notification cannot include the log body

Log-based alert annotations support only three template variables: `{{$value}}` (the aggregated value), `{{$threshold}}`, and `$<attribute-name>` for any attribute used in the query's **Group By** clause. There is no variable for the log body/message — and a `count()` aggregation discards the log lines entirely — so a notification can never render the text of the log that triggered it.

In practice this means the only way a per-log value reaches a Slack/webhook notification is as a **label**: either an attribute in the alert query's `groupBy` (dynamic labels) or one of the rule's static `labels`. The default Slack channel template renders `summary`/`description` plus every entry of `.Labels.SortedPairs`. Putting a high-cardinality field such as a place name or an id in `groupBy` turns one alert into one alert group per distinct value — a cardinality trap for "any log at severity X" rules. A dedicated rule filtered to the specific message and grouped by the field you want to see is the workable form.

The supported escape hatch is the auto-injected `related_logs` annotation, which the default Slack template renders as a "View in logs explorer" deep link filtered to the alert's query and time range: the log text is one click away, but never in the notification itself.
