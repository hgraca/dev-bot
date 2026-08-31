---
date: 2026-06-18
keywords: ["k8s", "deployment", "selector", "immutable", "gotcha"]
---

## Kubernetes Deployment spec.selector.matchLabels is immutable

Once a Deployment is created, `spec.selector.matchLabels` cannot be changed. Adding a new label (e.g. `OTEL_SERVICE_NAME`) to both `spec.template.metadata.labels` AND `spec.selector.matchLabels` causes ArgoCD sync failures with "field is immutable". The label must ONLY be added to `spec.template.metadata.labels` (pod template). When using sed to bulk-add labels to multi-document YAML files, ensure the label insertion targets only the template section, not the selector section.
