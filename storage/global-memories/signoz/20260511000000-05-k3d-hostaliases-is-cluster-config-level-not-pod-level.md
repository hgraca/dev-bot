---
date: 2026-05-11
keywords: ["signoz"]
---

## k3d hostAliases is cluster-config-level, not pod-level

Easy to assume `hostAliases` lives in a Kubernetes pod-spec (`spec.template.spec.hostAliases:`) — in this project it does not. The mechanism is the k3d top-level `hostAliases:` block in `<cluster>/cluster-config.yaml` (k3d v5.4+), rendered into k3s node `/etc/hosts` and propagated into pods at `k3d cluster create` time. Symptoms of confusion: `kubectl get deploy <name> -o yaml | grep hostAliases` returns nothing; doc readers cannot locate the mechanism in K8s manifests. Staleness failure: IPs are bound at cluster-create time, so restarting Docker or re-creating only one cluster (e.g. `make teardown-signoz && make up-signoz` without re-creating the producer cluster) stales the producer's mapping.
Fix: Inspect with `kubectl exec deploy/<name> -- cat /etc/hosts` (what pods actually see) and `grep -A4 hostAliases <cluster>/cluster-config.yaml` (source of truth). On staleness, re-create both clusters. See [[latent/PDRs]] cross-cluster DNS decision; first hit during Task 5 PR-2 review (commit `03251e0`).
