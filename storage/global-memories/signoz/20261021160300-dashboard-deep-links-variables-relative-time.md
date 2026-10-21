---
date: 2026-10-21
keywords: ["signoz", "dashboard", "variables", "relativeTime", "deep-link"]
aliases: ["dashboard URL variables", "pre-filtered dashboard link", "share dashboard link"]
---

## Deep-linking a SigNoz dashboard with variables and a time range

A dashboard URL accepts `?variables=<urlencoded JSON>` (e.g. `{"service":["transfers"]}` → `%7B%22service%22%3A%5B%22transfers%22%5D%7D`) and `?relativeTime=3h`. On load SigNoz applies both, then rewrites the URL: `variables` is dropped (the values persist in the browser store) and `relativeTime` is kept. The dashboard **id** in the path is server-assigned, so any link that hardcodes it is instance-bound — re-importing into another instance changes the id and the link must be updated. Use a relative time window, not an absolute one, because alert annotations expose no timestamp to anchor the range; pick a window longer than the rule's evaluation window so a freshly fired alert's deviation is inside it.
