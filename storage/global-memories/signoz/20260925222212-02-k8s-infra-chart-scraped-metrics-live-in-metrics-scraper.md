---
date: 2026-09-25
keywords: ["signoz", "helm", "prometheus", "pipeline"]
trigger-on: ["signoz-k8s-infra-custom-receiver"]
---

## In the SigNoz k8s-infra chart, scraped metrics flow through `metrics/scraper` — not `metrics`

The chart's deployment collector defines three pipelines — `logs`, `metrics/internal` and `metrics/scraper` — and its templates **append** their preset receiver to whatever is listed in `metrics/scraper.receivers`, so adding your own receiver to that list keeps the presets (`prometheus/scraper` and friends) intact. Declaring a pipeline literally named `metrics` instead sends the config down the _agent_ branch of the shared `applyResourceDetectionConfigForDeployment` helper, which prepends to a nil `processors` list and fails the whole render with `runtime error: invalid memory address or nil pointer dereference`. Custom receivers go under the top-level `otelDeployment.config.receivers` (whose chart default is literally `receivers: {}`) and are listed in `service.pipelines["metrics/scraper"].receivers`. Verify by rendering rather than reasoning: `helm template <release> signoz/k8s-infra --version <v> -f <values>` and read the produced ConfigMap. It takes seconds and catches this before anything reaches a cluster; a `presets.*` scrape job, by contrast, is the chart-supported path and needs no pipeline surgery at all.
