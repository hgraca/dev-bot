---
date: 2026-09-24
keywords: ["signoz", "notification-channel", "commonlabels", "groupby", "slack"]
trigger-on: ["signoz-channel-title", "signoz-alert-template-label"]
---

## A channel-title label must be in `notificationSettings.groupBy`, not just the query `groupBy`

A Slack channel title that renders a per-alert attribute — `[{{ index .CommonLabels "db" }}]` — only fills in when that attribute is in the rule's `notificationSettings.groupBy`. That list is Alertmanager's `group_by`, and `CommonLabels` is the intersection of the labels on every alert in the group, so only the group keys are guaranteed present: an attribute the alerts carry but `group_by` omits drops out as soon as two alerts in one group differ on it, and the title renders an empty bracket. A rule's **query** `groupBy` (the series split inside the builder) does not make a label common — the two lists are independent, and the query one usually holds many more attributes (`host`, `command`, `state`, `query_text`). The fix is to add the attribute to `notificationSettings.groupBy` as well, which also splits notifications per value — normally what you want when the title names it. Every title in this project that shows a per-alert label reads a group key (`service.name` in `[SERVICE]`, `job` in the `alerts-*` channels, `service.instance.id` in the redis title) for that reason.
