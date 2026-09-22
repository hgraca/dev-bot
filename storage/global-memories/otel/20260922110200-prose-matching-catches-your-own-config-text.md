---
date: 2026-09-22
keywords: ["otel", "log-matching", "argocd", "false-positive"]
trigger-on: ["log-body-matching", "argocd-helm-values-echo", "gitops-config-in-logs"]
---

## A log rule that matches on prose will fire on your own config text

Matching a log rule on the **body** is unsafe in a GitOps estate because config text ends up in other services' logs: `argocd-repo-server` logs the Helm values it renders, which embed the collector config verbatim — including the `IsMatch(body, "…")` strings themselves. A body-only rule keyed on `"access forbidden by rule"` therefore mapped argocd's config dumps to `NOTICE`/11 and looked like an nginx problem while nginx was innocent. The tell was that the affected records had an explicit `level: info` and **no** `status` attribute, so no legitimate mapping could have produced `NOTICE` — diagnosing it meant fetching one raw record and checking which statement *could* have fired, not just what fired. Two fixes, both worth applying: scope any body match by source, and prefer field-based conditions (`level`, `status`, `log_type`) over prose wherever a field carries the same information. The same reasoning generalises to any config-as-data system whose components log their inputs (ArgoCD, CI runners, manifest renderers).
