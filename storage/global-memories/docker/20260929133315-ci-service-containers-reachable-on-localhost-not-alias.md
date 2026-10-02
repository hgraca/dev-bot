---
date: 2026-09-29
keywords: ["docker", "ci", "service-container", "kafka", "localhost"]
trigger-on: ["ci-service-container-port", "compose-network-alias"]
---

## CI service containers are reachable on `localhost:<port>` from the job, not by their compose network alias

A GitHub Actions `services:` container is published to the runner host on its mapped port and may carry a `--network-alias`, but the job's steps run on the host, outside that network — so only `localhost:<port>` resolves; the alias (e.g. `kafka:9092`) does not. A test that hard-codes the compose alias is green inside the dev container (where the alias resolves) and red in CI with `Failed to resolve '<alias>'` / rdkafka "Name does not resolve", which reads like an infra outage rather than a test bug. Make integration tests read the endpoint from the same config/env the application uses (in this project `queue.connections.kafka.brokers`, fed by `KAFKA_BROKERS`, defaulting to the compose alias) and pass `localhost:<port>` in the CI job env; the workflow's advertised-listener setting must name the same host. Grep for the literal alias in tests — every hard-coded occurrence is a CI-only failure waiting to happen. To prove the env is actually honoured, point the variable at a bogus host and confirm the failure names that host.
