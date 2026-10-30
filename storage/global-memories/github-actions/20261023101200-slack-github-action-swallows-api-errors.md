---
date: 2026-10-23
keywords: ["github-actions", "slack-github-action", "notifications", "silent-failure"]
aliases: ["green notify job", "slack message never arrives", "chat.postMessage no delivery"]
trigger-on: ["slack-notification-step", "reusable-workflow-notify"]
---

## slack-github-action v4 hides every API error unless `errors: true`

`slackapi/slack-github-action@v4.0.0` runs `send()` inside a catch that, when the `errors` input is `false`
(its default), records nothing and rethrows nothing: a rejected `chat.postMessage` (`not_in_channel`,
`channel_not_found`, `missing_scope`, `invalid_auth`, `invalid_blocks`) leaves the step **green with zero
output**. The action also logs nothing on success, so an empty log proves neither delivery nor failure — a
green notify job can mean the message was silently dropped for months.

Set `errors: true` (the step then fails on a rejection) and add a follow-up step with `if: always()` that
echoes `steps.<id>.outputs.ok` and `steps.<id>.outputs.response` through `env:` — the response holds the
Slack error payload even when the step was allowed to pass. Related: pass `blocks` as a native YAML/JSON
array rather than a stringified JSON block scalar, and set `fail-fast: false` on a per-channel matrix so one
misconfigured channel does not cancel the rest.
