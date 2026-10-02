---
date: 2026-09-29
keywords: ["signoz", "kafka", "telemetry", "deployment"]
trigger-on: ["signoz-verify-deploy", "kafka-consumer-span-verification"]
---

## Verifying a just-deployed consumer's spans in SigNoz: confirm revision, then rule out idle

To verify that new consumer instrumentation reached a low-traffic environment, establish three things in order before declaring a bug. (1) **Confirm the deployed revision**: the `k8s-gete-dev` repo records each deploy as a commit `Update <service>: <branch> (<sha>)` — but **fetch first**, because a stale local clone still shows the pre-deploy digest and sends you hunting a phantom. (2) **Confirm traffic exists**: query the consumer's own log lines (e.g. `body CONTAINS 'Processing Message'`) — zero spans on a topic that received zero messages is a *healthy idle*, not a failure, and topics with `AUTO_OFFSET_RESET=latest` can sit silent for hours after a deploy. (3) **Pick attributes that discriminate *your* spans from the framework's**: a bare `messaging.system EXISTS` also matched Laravel queue spans (they carry `messaging.system`, e.g. `redis`) and a Consumer-kind `receive (anonymous)` span from queue instrumentation — so filter on a signal unique to the new span (here `messaging.kafka.offset EXISTS` plus `kind_string = 'Consumer'`, with the topic as the span name). Remember each window ends at query time, not at the deploy timestamp.
