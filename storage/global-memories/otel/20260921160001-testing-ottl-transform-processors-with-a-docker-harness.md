---
date: 2026-09-21
keywords: ["otel", "ottl", "transform-processor", "test-harness", "collector-config"]
trigger-on: ["otel-collector-transform", "ottl-processor", "collector-config-change"]
---

## Testing OTTL transform processors without a cluster: Docker collector plus file exporter

Collector `transform`/OTTL config is normally untestable until it reaches a cluster, which turns every severity or attribute change into a production gamble. The pattern that works: run `otel/opentelemetry-collector-contrib:<version>` under Docker with a minimal throwaway config (`otlp` receiver on 4318 → the processor under test → `file` exporter writing `/out/out.json`), POST synthetic log records as OTLP/JSON, then read the exporter output and assert on `severityNumber`/`severityText` and the emitted attributes. Build the payload as `resourceLogs[].scopeLogs[].logRecords[]` with `body: {stringValue: <case-name>}` (so results map back to fixtures) and attributes as `{"key":k,"value":{"stringValue":v}}`, `{"intValue":"500"}` for numbers, or `{"kvlistValue":{"values":[...]}}` for nested maps. Three things that matter: pin the image to the exact version the cluster runs, so the result transfers (the `k8s-infra` 0.16.0 chart ships contrib 0.139.0); the file exporter emits one JSON document per flush, so split on `}\n{` before parsing; and when the change is a type normalisation, assert on attribute **value kinds** (`intValue` vs `stringValue`), not just values, or the test passes on the unfixed config too.
