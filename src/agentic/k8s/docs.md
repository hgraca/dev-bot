---
title: "K8s"
description: "Kubernetes manifest linting and cluster access."
skills: ["lint-k8s", "k8s-access"]
hooks: ["lint-k8s"]
tools: ["lint-k8s"]
---

Audits Kubernetes, Kustomize, and Helm manifests with `kubeconform` (schema validation) and `kube-linter` (best practices), and renders the kubeconfig agents use to reach a cluster.

## How agents use it

Auto-lints on file save when editing K8s YAML files. Agents can also invoke it explicitly to validate manifests before deployment.

## Cluster access

`init.sh` reads the `kubectl` node of the global config — a catalogue of
clusters — together with the project's `kubectl` list of cluster names to opt
into. It writes **two files per project**:

```
~/.kube/devbot/<project_name>-<8-hex>.yaml   the kubeconfig
~/.kube/devbot/<project_name>-<8-hex>.env    the credential file
```

`<8-hex>` is the first eight characters of the sha256 of the project's absolute
path, so two checkouts that share a directory name keep separate files. Neither
name is guessable — resolve them with `devbot kube` rather than listing the
directory.

The context names come from each catalogue entry's `context` field. In the
default catalogue that is `gete-prod-ro` (read-only production) and
`gete-staging-rw` (staging); the identity lands in the `gete-agents-readonly` and
`gete-agents-writer` groups. **Do not use `~/.kube/config`** — its contexts are
SSO exec contexts that expire; these use the devbot profile.

### Using it

```sh
devbot kube env      [path]   # KUBECONFIG + current context (no credentials)
devbot kube contexts [path]   # cluster name, context, region
devbot kube run      [path] -- get pods -n core
```

`devbot kube run` sources the project's `.env` inside a subshell — credentials
never reach the caller's environment and are never printed — then execs
`kubectl --kubeconfig <file>`.

The generated config is **not** merged into `~/.kube/config`. If you must call
`kubectl` yourself, point it at the generated file explicitly:

```sh
devbot kube env my-project        # prints the KUBECONFIG path and context name
kubectl --kubeconfig <path> --context gete-staging-rw get pods -n core
```

The files are rendered, not read live: after changing the project's `kubectl`
selection or the global catalogue, run `devbot reinit <path>`.

RBAC boundaries, what the reader and writer groups grant, and the exec
restriction are documented in the `k8s-access` skill.

## Configuration

Cluster access needs a `kubectl` node in the global config plus a `kubectl`
list of cluster names in the project; linting needs nothing. See the `kubectl`
section of [configuration](/docs/configuration) for the shape, and note that
credential values stay in the environment — the generated wrapper carries a
`${VAR}` reference, never a key.

## See also

- [Supervisor sessions](/supervisor-sessions) — how this module scopes itself to the owning project
- [Docker](/module-reference) — Dockerfile authoring patterns
