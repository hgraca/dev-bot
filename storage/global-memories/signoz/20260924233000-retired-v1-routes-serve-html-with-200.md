---
date: 2026-09-24
keywords: ["signoz", "dashboard-api", "saved-views", "v1-retired", "http-200"]
trigger-on: ["signoz-api-client", "signoz-v1-api"]
---

## Retired SigNoz V1 routes answer with the SPA's HTML and HTTP 200, not 501

SigNoz v0.135.0+ retires `/api/v1/dashboards` and v0.137.0 deprecates `/api/v1/explorer/views`, and the docs say the retired routes return `501 Not Implemented` (`dashboard_deprecated`). On the actual instance they do not: a request to `/api/v1/dashboards` — GET or POST — comes back with the frontend's **HTML and HTTP 200**. Any client that trusts the status code therefore appears to succeed while writing nothing, and a trailing `jq` parse of that HTML fails with a confusing error far from the cause. The tooling in this repo rejects a non-JSON body outright for exactly this reason, and the same guard must accept a 204 with an empty body (a saved-view update answers that) without treating it as the HTML failure.
