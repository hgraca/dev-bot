---
date: 2026-06-15
keywords: ["otel", "ottl", "replace_all_strings", "ReplacePattern", "argocd"]
---

## OTTL replace_all_strings vs ReplacePattern in ArgoCD-managed ConfigMaps

When using OTTL transform processors in OTel Collector config stored as an ArgoCD-managed ConfigMap, always use `replace_all_strings` instead of `ReplacePattern`. `replace_all_strings` is a standalone OTTL function that mutates the target in place — no `set()` wrapper needed. `ReplacePattern` is regex-based, requires a `set()` wrapper, and its regex escaping (`\\.`) breaks during ArgoCD's YAML→JSON→YAML serialization roundtrip, causing `undefined function "ReplacePattern"` errors. `replace_all_strings` does literal substring replacement, so drop regex anchors (`^`, `$`) and unescape dots (use `".eu-central-1.compute.internal"` not `"\\.eu-central-1\\.compute\\.internal$"`).
