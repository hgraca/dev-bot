---
date: 2026-11-03
keywords: ["kubectl", "kubeconfig", "devbot kube", "rbac"]
aliases: ["cluster access", "gete-prod-ro", "pods/exec denied"]
---

# Cluster access goes through `devbot kube`

## The generated kubeconfig is not guessable

`init.sh` writes `~/.kube/devbot/<project_name>-<8-hex>.yaml` (the hash is of the absolute project path) plus a `.env` that contains **only** `export KUBECONFIG=…` — no credentials. Contexts come from the global catalogue's `context` field (`gete-prod-ro`, `gete-staging-rw`). Before `devbot kube` existed, the module's `docs.md` named a non-existent `<project>.yaml` and `k8s-prod-ro`, so agents fell back to the SSO contexts in `~/.kube/config` and hit `Token has expired and refresh failed`.

## RBAC boundaries

The identity lands in `gete-agents-readonly` (cluster-wide get/list/watch, no secrets, exec, port-forward or token creation) and `gete-agents-writer` (staging only, namespaced to `default`). `pods/exec` is denied by design — use the `datasources` module or SigNoz metrics instead of exec-ing into a pod. Because the writer Role is namespaced to `default`, `core`, `kube-system`, `argocd` and `otel-collector` stay read-only even on staging.
