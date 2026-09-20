---
date: 2026-09-11
keywords: ["otel", "resourcedetection", "collector", "availability-zone"]
trigger-on: ["otel-resourcedetection-remote-scrape"]
---

## resourcedetection stamps the collector node's AZ onto remote-scraped metrics, splitting series

An OTel collector's `resourcedetection` processor (ec2/eks detectors) adds `cloud.availability_zone` from the node the collector runs on — including for metrics scraped from a remote target such as an RDS exporter, where the AZ is meaningless. When the collector pod reschedules across AZs, one metric splits into overlapping series (one per AZ). Aggregations that `sum` then double-count, and `rate()` reads the label change as a counter reset — which is what produced duplicate `production …` lines in SigNoz. Fix at the detector for the relevant deployment: `resourcedetection: {ec2: {resource_attributes: {cloud.availability_zone: {enabled: false}}}, eks: {resource_attributes: {cloud.availability_zone: {enabled: false}}}}`. After the fix the attribute is emitted as an empty string rather than absent, so group-by returns a single series. Before blaming a panel's legend, confirm the split is current with `signoz_get_field_values` / a grouped metrics query over a recent window.
