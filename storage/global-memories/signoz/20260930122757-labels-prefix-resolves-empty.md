---
date: 2026-09-30
keywords: ["signoz", "alert-rule", "annotation", "template", "labels"]
trigger-on: ["signoz-alert-rule-annotation", "signoz-notification-template"]
---

## Any `$labels.` prefix in a rule annotation resolves empty

SigNoz's rule template expander (`pkg/types/ruletypes/templates.go`, `preprocessTemplate()`) rewrites `{{$<name>}}` to `{{index .Labels "<name>"}}` using the regex `{{\s*\$\s*([a-zA-Z0-9_.]+)\s*}}`, which captures the name whole — so `{{$labels.group}}` becomes a lookup of a label literally named `labels.group`, which never exists, and renders the empty string with no error (`missingkey=zero`). `{{$labels.deployment.environment}}` and `{{$labels.service.name}}` fail identically. Verified on v0.143.0 against the live `Kafka consumer lag high` rule, whose description read "Consumer group  is 575 messages behind on topic  ()". The correct form is the bare attribute name as it appears in the query's groupBy — `{{$group}}`, `{{$topic}}`, `{{$deployment.environment}}` — the same form `Long-running query` uses with `{{$host}}`; `{{$value}}` and `{{$threshold}}` are special-cased and pass through. Do not trust the SigNoz MCP's own `signoz://alert/instructions` advice to use `{{$labels.key}}` (e.g. `{{$labels.k8s_pod_name}}`) — that is exactly the form that breaks. `AlertTemplateData` also inserts a `NormalizeLabelName`'d copy of each key (dots and non-alphanumerics → `_`), so `{{$deployment_environment}}` also works. Guarded by `scripts/test/validate-alerts.sh` check 9, which fails any annotation containing the `$labels.` prefix.
