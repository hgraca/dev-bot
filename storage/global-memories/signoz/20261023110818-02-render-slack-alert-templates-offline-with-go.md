---
date: 2026-10-23
keywords: ["signoz", "slack_configs", "text/template", "alertmanager", "recovery"]
aliases: ["render alert template locally", "test slack template offline", "verify recovery wording"]
trigger-on: ["signoz-alert-channel-edit", "signoz-alert-template-wording"]
---

## Render a SigNoz Slack template locally before applying it

SigNoz notification channels carry Go/Alertmanager templates, and the only in-product way to see the output is to wait for a real alert — so a wording change, and especially a new `.Status` branch for resolved notifications, otherwise ships untested. Extract the template with `jq -r '.channels[] | select(.name=="<channel>") | .text'` (SigNoz's channel `data` is a JSON string, so the live equivalent needs `fromjson` first), then execute it with Go `text/template`, stubbing only the Alertmanager functions it uses (`tz` as `func(loc string, t time.Time) time.Time`, `date` as `func(layout string, t time.Time) string`) against a literal alert holding `Status`, `Annotations`, `CommonLabels` and `StartsAt`; render twice with `"firing"` and `"resolved"` and read both bodies. This proves the exact wording, catches a template parse error that would otherwise break every notification on that channel silently, and costs one scratch program instead of a live fire-and-resolve cycle.
