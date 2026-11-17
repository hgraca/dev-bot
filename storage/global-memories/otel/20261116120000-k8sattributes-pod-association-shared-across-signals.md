---
date: 2026-11-16
keywords: ["otel", "k8sattributes", "pod_association", "logs", "passthrough"]
aliases: ["connection fallback", "IP-based pod association", "drop connection source"]
trigger-on: ["k8sattributes-pod-association"]
---

## k8sattributes pod_association is shared by every signal, so k8s.pod.uid is an output for logs

One `k8sattributes` processor instance serves every pipeline that names it, so editing its `pod_association` changes association for logs, traces and metrics at once. For **traces** the workload can supply `k8s.pod.uid` itself (downward API into `OTEL_RESOURCE_ATTRIBUTES`), which makes removing the trailing `connection` source (source-IP lookup) safe. For **logs it is not**: an OTel collector's filelog/container parser sets `k8s.pod.name` and `k8s.container.name` from the log path but never `k8s.pod.uid`, so on a log record the UID is the *result* of association, not an input. Remove `connection` and there is nothing left to associate on; with `passthrough: false` the records are dropped silently — in one production cluster that would have been ~305,000 log lines per 10 minutes. The gateway collector has the same trap for scraped metrics: exporter pods are matched by `connection`, so dropping it blanks every scraped series. Verify before changing: grep the values file for `k8s.pod.uid` — if it appears only under `extract.metadata`, no receiver supplies it and the IP fallback is load-bearing. To harden trace attribution without touching logs, add a second processor (`k8sattributes/traces`) with UID-only association and wire it into the traces pipeline alone.
