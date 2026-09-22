---
date: 2026-09-22
keywords: ["k8s", "configmap", "helm", "grep", "yaml"]
trigger-on: ["configmap-content-verify", "helm-render-inspect", "grep-rendered-manifest"]
---

## Grepping rendered/deployed YAML for a phrase false-negatives when the phrase wraps

Long scalars are emitted **wrapped** by the YAML serializer, so a phrase that reads as one string in the source can be split mid-phrase in the output: the source line `- set(severity_number, SEVERITY_NUMBER_INFO3) where IsMatch(body, "access forbidden by rule")` renders and deploys as `... IsMatch(body, "access forbidden` + newline + `  by rule")`. A `grep -c 'access forbidden by rule'` then returns `0` against a manifest that genuinely contains the rule, which reads as "the change did not deploy" and sends you chasing a phantom. This bites twice over: once on `helm template` output and once on the live object (`kubectl get cm ... -o jsonpath='{.data.config\.yaml}'`). The fix is to grep for a **non-wrappable marker** — an identifier, function name (`IsMatch`), operator `id`, or key — rather than prose; a phrase is only safe if it is short enough to stay on one line. When a negative result drives a conclusion ("not deployed"), confirm it with a second, structurally different marker before believing it, and prefer `yq -r`/`tr -d '\n'` to normalise wrapping when you must match prose.
