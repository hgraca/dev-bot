---
date: 2026-09-24
keywords: ["signoz", "dashboard-migration", "legacy", "panelMap", "v2"]
trigger-on: ["signoz-dashboard-migration", "signoz-v1-to-v2-conversion"]
---

## A V1 dashboard with `panelMap` as an array fails V2 conversion and lands `legacy`

The v0.135.0 migration converts dashboards to the V2 schema in place, and a dashboard it cannot convert stays on the old schema flagged `legacy: true` (`schemaVersion: "v5"`) where it is listed but cannot be opened. The failure is data-shaped, not schema-shaped: a V1 dashboard whose `panelMap` is an **empty array** (`[]`) fails the converter, which the V1→V2 create shim names exactly — `malformed v1 dashboard fields: "panelMap" has unexpected type []interface {}`. The field must be an **object or null**; every healthy dashboard carries `{}` or `null`. Changing `[]` to `{}` is faithful when the array is empty and makes the conversion succeed (`201`, `schemaVersion: "v6"`, panels/tags/image preserved), so a legacy dashboard is repairable rather than lost — worth diffing `panelMap`'s type across dashboards before concluding a rebuild is needed.
