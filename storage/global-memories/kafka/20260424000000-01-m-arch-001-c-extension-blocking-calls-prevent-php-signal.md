---
date: 2026-04-24
keywords: ["kafka", "consumer", "rdkafka"]
---

## M-ARCH-001: C-extension blocking calls prevent PHP signal dispatch

Kafka consumer's `consume()` called `rdkafka`'s C `consume()` with a 120s timeout. PHP signal handlers (SIGTERM from k8s) only fire between C calls — never during. Pods were SIGKILL'd before the C call returned.
When a PHP library wraps a C extension that blocks for a long time, introduce a short-poll loop: call the C function with a short timeout in a loop, letting PHP regain control between iterations. The library should NOT register signal handlers — that's the application's responsibility. The library's job is to yield control frequently enough.
