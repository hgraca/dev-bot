---
date: 2026-10-07
keywords: ["otel", "message-bus", "spans", "ingestion-cost"]
aliases: ["span volume increase", "message-bus consumer spans", "trace volume step change"]
trigger-on: ["message-bus-version-upgrade", "otel-span-volume"]
---

## Bumping get-e/message-bus past 0.17.19 multiplies exported span volume (~2.7x)

Measured on audit-log's production deploy of `get-e/message-bus` 0.17.16.0 → 0.17.22.0 (2026-10-07, k8s cluster `gete`): total span volume rose from ~265k to ~715k across equal 14-minute windows either side of the rollout (~2.7x), while job/traffic counts stayed flat (~40k `process queue job`, ~43k `receive`). The growth is per-message middleware spans: `MessageValidatorMiddleware` 5.8k → 57k, and each of ~13 other bus middlewares ~2.8k → ~28.6k (roughly 10x per processed message). The driver is 0.17.19's per-message consumer span — the bus opens and parents a span per consumed message, in isolation when no producer `traceparent` arrives (see the `message-bus owns the consumer span` note) — so upgrading a high-throughput consumer past 0.17.19 should be expected to raise trace ingestion and cost by a similar factor; size it by comparing equal-length windows before/after the rollout, not a fixed pre/post range.
