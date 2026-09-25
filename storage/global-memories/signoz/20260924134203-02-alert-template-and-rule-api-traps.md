---
date: 2026-09-24
keywords: ["signoz", "alert-rule", "annotation", "template", "api"]
trigger-on: ["signoz-alert-rule-annotation", "signoz-test-notification", "signoz-rule-disabled"]
---

## SigNoz alert-template and rule-API traps that all fail silently

Four traps, none of which errors. **Annotation variables are `$<attribute>` with a dot** — `{{$service.name}}`, `{{$deployment.environment}}` — alongside `{{$labels}}`, `{{$value}}` and `{{$threshold}}`; writing `{{$labels.service_name}}` resolves to the empty string, so the message reads "from " instead of naming anything. **`{{$value}}` already carries the unit** when the rule's unit is `percent`, so a template that appends its own `%` renders `66.7%%`. **`disabled: true` is ignored when a rule is created but honoured when it is updated**, so a rule created disabled still evaluates and pages — a manifest declaring `disabled` can be legitimately live — and the only way to silence it is a `PUT` carrying the flag, which is also why re-applying an always-disabled manifest switches alerts off. **The test-notification route is `POST /api/v2/rules/test` with the rule body** as the payload, answering `{"data":{"alertCount":N,"message":"notification sent"}}`; `POST /api/v2/rules/{id}/test` returns the SPA's HTML with a 200 and notifies nobody, and `/api/v1/rules/test` likewise sends nothing — a 200 from either is not success. Note also that with `alertCount: 0` the notification is sent but carries no alerts, so it renders empty and proves nothing about the template.
