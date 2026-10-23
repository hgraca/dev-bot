---
date: 2026-10-23
keywords: ["signoz", "resolved-notification", "alert-annotations", "status", "recovery"]
aliases: ["recovery message", "resolved alert template", "send_resolved template"]
trigger-on: ["signoz-alert-channel-template", "signoz-resolved-notification"]
---

## Resolved SigNoz notifications reuse the firing annotations unless the channel branches on Status

A rule's `annotations` are rendered for the resolved notification too, using the current evaluation value — so a summary of the form `{{$value}} degraded pod(s) ...` reads `0 degraded pod(s) ...` on recovery, and a firing `description` that tells the reader to delete the Failed pods is actively wrong once they are gone. Annotations are one set per rule and cannot change with status. To differ, add separate annotations (for example `recovery_summary` and `recovery_description`) and branch in the channel's `title`/`text` on `{{ if eq .Status "resolved" }}`. `.Status` is available in the channel title and inside `range .Alerts`, while `.CommonLabels` carries only the labels common to the notification group (namespace, environment, alertname, severity, team) — the per-alert value must come from `(index .Alerts 0).Annotations.value`.
