---
date: 2026-04-29
keywords: ["istio"]
---

## Removing YAML annotations can leave empty `annotations:` blocks

When a pod template's only annotation (e.g. `proxy.istio.io/config`) is removed, the parent `annotations:` key remains with no children. This becomes `null` in YAML and can fail Kubernetes schema validation for map fields. Always remove the parent key too.
