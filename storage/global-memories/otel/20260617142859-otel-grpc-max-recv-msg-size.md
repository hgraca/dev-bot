---
date: 2026-06-17
keywords: ["otel", "grpc", "otlp", "collector", "configmap"]
---

## OTel collector gRPC receiver defaults to 4MB max message size

The OTel collector gRPC receiver has a default `max_recv_msg_size_mib` of 4MB, which causes `ResourceExhausted: grpc: received message after decompression larger than max 4194304` errors when producers (e.g., filelog daemonsets, large-batch exporters) send payloads exceeding 4MB. Set `max_recv_msg_size_mib: 32` (or higher) under `receivers.otlp.protocols.grpc` in the collector config to accommodate batched log/metric payloads.
