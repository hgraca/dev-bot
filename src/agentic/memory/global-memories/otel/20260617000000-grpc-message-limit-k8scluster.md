---
date: 2026-06-17
keywords: ["otel", "grpc", "batch", "k8scluster"]
---

## Adding k8scluster metrics can exceed gRPC 4MB message limit — reduce batch size

When a collector has kubeletstats + KSM + hostmetrics receivers and you add the k8scluster receiver, the combined metrics payload can exceed the gRPC default max message size of 4MB. The error is: `rpc error: ResourceExhausted — received message after decompression larger than max 4194304`. This causes the exporter queue to overflow with "Exporting failed. Dropping data." and the pod eventually crashes from memory pressure. Fix: reduce `batch` processor `send_batch_size` from 8192 to 1000 or lower. The error occurs even with gzip compression because decompressed size on the server exceeds the limit.
