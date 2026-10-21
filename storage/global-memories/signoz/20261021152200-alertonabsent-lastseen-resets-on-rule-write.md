---
date: 2026-10-21
keywords: ["signoz", "alertOnAbsent", "lastSeen", "nodata", "alert-rules"]
aliases: ["false missed alert after apply", "lastSeen resets", "[No data] prefix"]
trigger-on: ["signoz-absent-rule", "signoz-apply-alerts"]
---

## An absent-data alert's `lastSeen` resets whenever the rule is written

SigNoz keeps `lastTimestampWithDatapoints` **in memory per rule** (`BaseRule.HandleMissingDataAlert`): a `PUT /api/v2/rules/{id}` — including a no-op rewrite from an apply script that upserts every manifest — zeroes it, and the very next evaluation whose `evalWindow` contains no matching data returns a missing sample immediately, without waiting `absentFor`. Such a false alert is recognisable by its label set: it carries `nodata: true` and **no `lastSeen`**, because `lastSeen` (the last evaluation timestamp that saw data) is only written when the counter is non-zero. Two consequences: an apply that rewrites every rule produces a burst of false `[No data] <rule>` alerts (three cron rules fired within a minute of one such apply while every job was running fine), and the durable fix is to make the apply skip rules whose manifest already matches the live rule instead of writing them again. Three related facts: SigNoz rewrites the `alertname` label to `[No data] <name>` whenever a rule fires from the absence path, so a notification title reading `alertname` shows that prefix — read your own label instead; once data returns, the alert clears only after Alertmanager's resolve timeout, because the missing-sample label set never recurs; and `evalWindow` is the only lever on how quickly absence is even detectable, so widening it to avoid empty windows also delays detection by roughly the same amount.
