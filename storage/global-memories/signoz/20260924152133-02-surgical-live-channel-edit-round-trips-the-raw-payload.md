---
date: 2026-09-24
keywords: ["signoz", "notification-channel", "mcp", "api", "slack-configs"]
trigger-on: ["signoz-update-notification-channel", "signoz-update-alert", "signoz-surgical-live-edit"]
---

## Changing one live SigNoz object: round-trip the raw payload, not the MCP update tool

`signoz_update_notification_channel` accepts only `name`, `type`, `slack_api_url`, `slack_channel`, `slack_title`, `slack_text` and `send_resolved`, but a live Slack channel also stores `app_url`, `http_config`, `username`, `color`, `title_link`, `pretext`, `footer`, `fallback`, `callback_id`, `icon_emoji`, `icon_url` and `timeout` — written explicitly by `scripts/setup-alerts.sh`, not filled in as server defaults — so an MCP update silently thins the stored config and diverges from the repo's complete-record `channels.json`. `signoz_update_alert` has the mirror problem: its schema says to omit `preferredChannels` for v2 threshold rules, dropping a field the live rule still carries. For a surgical live change, GET the object and PUT the payload back with only the target field patched, using the same shape `setup-alerts.sh` sends: `GET /api/v1/channels/{id}` hands back the payload as a JSON **string** (`.data.data | fromjson`, needs `type` re-added for the PUT), while `GET /api/v2/rules/{id}` returns `.data`, from which the script deletes `state`, `source`, `createdAt`, `createdBy`, `updatedAt`, `updatedBy` and re-adds `id` in the body. Both PUTs answer `204`, and `disabled` survives the round-trip — so an enabled rule stays enabled, unlike `make alerts-setup`, which re-issues the disable `PUT` for every manifest declaring `disabled: true`.
