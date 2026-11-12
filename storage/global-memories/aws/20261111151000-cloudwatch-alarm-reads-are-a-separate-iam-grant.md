---
date: 2026-11-11
keywords: ["aws", "cloudwatch", "iam", "describealarms"]
aliases: ["alarm history permission", "cloudwatch reads do not cover alarms"]
trigger-on: ["cloudwatch-alarm-read", "incident-alarm-timeline"]
---

## CloudWatch alarm reads are a separate IAM grant from metric reads

`cloudwatch:GetMetricData`, `GetMetricStatistics` and `ListMetrics` are their own actions, and having them
tells you nothing about alarm access. An identity that can pull a metric series all day still gets
`AccessDenied … no identity-based policy allows the cloudwatch:DescribeAlarms action` the moment it asks
for the alarm — the denial names only the one action, which reads as a broken tool rather than a missing
grant. Two actions are needed and they are not interchangeable: `cloudwatch:DescribeAlarms` returns the
current state and configuration (threshold, comparison, `Statistic`, `Period`, `EvaluationPeriods`,
`DatapointsToAlarm`, `TreatMissingData`, `AlarmActions`, `OKActions`), while
`cloudwatch:DescribeAlarmHistory` returns the state-transition timeline. `DescribeAlarms` alone reports a
single `StateUpdatedTimestamp`, so the ALARM→OK duration — usually the first thing to establish in an
incident — is only available from the history call, filtered with `HistoryItemType=StateUpdate`.

Both are granted on `"Resource": "*"` in practice, matching the sibling metric actions (which do not
support resource-level scoping at all). Read them before acting on a page: an alarm whose `OKActions` is
empty has told nobody it recovered, so an "open incident" can describe a condition that ended hours ago,
and a `Period` of 900 with `DatapointsToAlarm` 1 pages on a single transient average.
