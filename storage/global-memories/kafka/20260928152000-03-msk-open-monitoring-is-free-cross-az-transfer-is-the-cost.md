---
date: 2026-09-28
keywords: ["kafka", "msk", "open-monitoring", "cost"]
trigger-on: ["msk-open-monitoring", "prometheus-scrape-cost"]
---

## MSK Open Monitoring is free to enable; the cross-AZ scrape traffic is the cost

Enabling Open Monitoring on MSK (`aws kafka update-monitoring --open-monitoring`, JMX on `:11001` and node exporter on `:11002`) carries **no AWS charge** — the fees quoted around MSK "monitoring" belong to the Enhanced monitoring tiers (`PER_TOPIC_PER_PARTITION`) and to CloudWatch's own hosted Prometheus collector, neither of which this is. The only new cost is data transfer: the brokers sit one per AZ while the scraping collector pods do not, and AZ-to-AZ traffic is billed **in both directions** ($0.01/GB each per the Cost and Usage Report guidance, so ~$0.02/GB). Size it from the payload fetched at scrape time rather than from what lands in the backend: the JMX endpoint returns on the order of 1.2 MB per scrape on a small cluster, which is ~3.4 GB/day per broker at a 30s interval, while the exported OTLP is compressed and far smaller. The scrape interval is the single lever — 60s halves it, and nothing else about the endpoints is tunable.
