---
date: 2026-09-10
keywords: ["signoz", "alert-rule", "disabled", "create", "api"]
trigger-on: ["signoz-alert-rule", "signoz-create-alert"]
---

## SigNoz create alert ignores `disabled: true` — an update is required to actually disable it

Creating a SigNoz alert rule with `disabled: true` (POST /api/v2/rules, or the MCP create tool) stores the flag but does NOT put the rule into the disabled runtime state: the rule is still evaluated once on creation and can fire notifications (observed: a rule created `disabled: true` fired for 11 pods ~13s later and posted to Slack). An explicit update (PUT /api/v2/rules/{id}) carrying `disabled: true` is what transitions the rule to `state: "disabled"`. Any tooling that creates rules from manifests must issue a second (update) call when the manifest sets `disabled: true`.
