---
title: "K8s"
description: "Kubernetes manifest linting and cluster access."
skills: ["lint-k8s"]
hooks: ["lint-k8s"]
tools: ["lint-k8s"]
---

Audits Kubernetes, Kustomize, and Helm manifests with `kubeconform` (schema validation) and `kube-linter` (best practices), and renders the kubeconfig agents use to reach a cluster.

## How agents use it

Auto-lints on file save when editing K8s YAML files. Agents can also invoke it explicitly to validate manifests before deployment.

## Cluster access

`init.sh` reads the `kubectl` node of the global config — a catalogue of
clusters — together with the project's `kubectl` list of cluster names to opt
into. It writes `~/.kube/devbot/<project>.yaml`, that project's `.env`, and one
shared exec credential wrapper. Everything is derived, so the kubeconfig is
regenerated on every init and never edited by hand. A project that names no
clusters gets none, and each project's file is its own: one project's selection
cannot widen another's.

The generated config is **not** merged into `~/.kube/config`. Point kubectl at it
explicitly:

```sh
. ~/.kube/devbot/<project>.env
kubectl --context k8s-prod-ro get pods
```

## Configuration

Cluster access needs a `kubectl` node in the global config plus a `kubectl`
list of cluster names in the project; linting needs nothing. See the `kubectl`
section of [configuration](/docs/configuration) for the shape, and note that
credential values stay in the environment — the generated wrapper carries a
`${VAR}` reference, never a key.

## See also

- [Supervisor sessions](/supervisor-sessions) — how this module scopes itself to the owning project
- [Docker](/module-reference) — Dockerfile authoring patterns
