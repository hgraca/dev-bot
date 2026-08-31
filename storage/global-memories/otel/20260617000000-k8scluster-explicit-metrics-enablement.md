---
date: 2026-06-17
keywords: ["otel", "k8scluster", "metrics", "v0.154.0"]
---

## k8scluster receiver needs explicit metric enablement in v0.154.0

In OTel Collector contrib v0.154.0, the k8scluster receiver's default metrics (`k8s.deployment.available`, `k8s.daemonset.*`, `k8s.statefulset.*`, `k8s.job.*`, `k8s.cronjob.*`, `k8s.pod.phase`, `k8s.namespace.phase`) may not be emitted without explicit `metrics:` enablement in the receiver config. The receiver starts cleanly ("Starting k8sClusterReceiver without leader election") and watches resources (RBAC errors confirm active reflectors) but no metrics reach the exporter. Fix: add `metrics:` section under `k8s_cluster:` explicitly enabling each desired metric with `enabled: true`. Also add `otlp_grpc` exporter rename and reduce batch `send_batch_size` to 1000 to avoid gRPC 4MB message limit when combined with KSM + kubeletstats + hostmetrics.
