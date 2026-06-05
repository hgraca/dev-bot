---
date: 2026-04-22
keywords: ["k8s", "cluster"]
---

## G-006: StatefulSet requires matching headless Service

- **Problem**: `spec.serviceName` must point to an existing Service. If the Service doesn't exist, the manifest may be rejected or pod DNS won't work.
  Create a headless Service (`clusterIP: None`) with `selector` matching the StatefulSet's pod labels.
