---
date: 2026-10-09
keywords: ["k8s", "kubectl", "configmap", "rollout", "deployment"]
aliases: ["configmap change not applied", "kubectl apply no-op", "pods keep old config", "deploy-otel-prod does not roll"]
trigger-on: ["k8s-configmap-volume-change", "k8s-deploy-rollout", "kubectl-apply-unchanged-spec"]
---

## A ConfigMap-only change never reaches running pods — `kubectl apply` of an unchanged pod spec is a no-op

A Deployment/DaemonSet that mounts a ConfigMap does not restart when the ConfigMap changes: `kubectl apply -f deployment.yaml` compares only the pod template, which is identical, so it reports `unchanged` and no rollout happens. The kubelet refreshes the mounted file within ~a minute, but the process read its config once at startup and (for an OTel collector) never reloads. A deploy target that applies ConfigMaps and then only `kubectl rollout status`-waits therefore silently skips config-only changes until someone restarts the workload by hand — the fix that finally reached the pods only because a human ran `kubectl rollout restart`. Remedy: after applying the ConfigMaps, explicitly `kubectl rollout restart deployment/<x> daemonset/<y>` (safe at low replica counts — a rolling restart surges the new pod before removing the old), or stamp a `checksum/config` annotation on the pod template so the template changes only when the config content does (the Helm pattern), avoiding a needless restart on every deploy.
