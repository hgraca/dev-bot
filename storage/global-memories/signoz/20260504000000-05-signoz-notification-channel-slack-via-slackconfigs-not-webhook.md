---
date: 2026-05-04
keywords: ["signoz"]
---

## SigNoz notification channel: Slack via slack_configs, not webhook

To create a Slack channel, POST to `/api/v1/channels` with `{name, type:"slack", slack_configs:[{api_url:<webhook>, channel:"#name", send_resolved:true, title:"...", text:"..."}]}`. Despite storing `type: "webhook"` in the outer response, the `data` field correctly contains `slack_configs` and alerts fire to Slack. Use PUT `/api/v1/channels/<id>` to update an existing channel (idempotent re-runs).
