---
date: 2026-11-27
keywords: ["k8s", "kustomize", "yaml", "lists"]
aliases: ["hostnames list shape", "list item indentation"]
---

## kustomize writes lists indentless, so a hand-written fixture lies

kustomize emits a sequence as `key:` followed by `- item` at the **same** indentation as the key, not indented under it:

```yaml
  hostnames:
  - t01.transfers.get-e.dev
```

A parser written against a hand-written fixture that indents the item (`    - host`) silently matches nothing on real output — and the code that depends on it skips its work without an error. When a text parser reads kustomized YAML, accept the item at any indentation relative to the key, and keep a fixture rendered by kustomize itself (or one written indentless) so the test fails when reality does.
