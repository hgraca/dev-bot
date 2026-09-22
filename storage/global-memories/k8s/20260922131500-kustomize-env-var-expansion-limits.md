---
date: 2026-09-22
keywords: ["k8s", "kustomize", "env", "configmap", "downward-api"]
trigger-on: ["env-var-injection", "configmap-to-env-migration", "downward-api"]
---

## `$(VAR)` expands only in container `env` — never in a ConfigMap, and only downwards in the list

Kubernetes substitutes `$(VARNAME)` only in a container's `env[].value`, and only from variables declared **earlier in that same container's `env` array** — so a Downward API value works as a source as long as it precedes its use (`- name: HOST_IP valueFrom: fieldRef: status.hostIP` immediately before `OTEL_EXPORTER_OTLP_ENDPOINT: $(HOST_IP):4317`). A `$(VAR)` in a `kustomize` `configMapGenerator` literal, in a ConfigMap's `data`, or in any envFrom-sourced key is **never** expanded — it stays as the four-character sequence `$(VAR)` and the workload resolves a hostname literally named `$(HOST_IP)`, which fails silently at runtime rather than at apply time. That is why a value needing node-local substitution must be moved out of a ConfigMap into container `env`, and why `env` vs `envFrom` collision resolution matters (`env` wins).

Two related traps. First, the JSON-patch form used to inject a full env list — `op: add, path: /spec/template/spec/containers/0/env, value: [...]` — **replaces** the array, silently dropping pre-existing entries such as `PORT`; append with `path: .../env/-` instead, one `add` per entry, and keep source-before-use order. Second, the pod spec always shows the *unexpanded* reference: `kubectl get deploy -o jsonpath` proves nothing about the resolved value. Read it from inside the container with `kubectl exec <pod> -c <container> -- env` (or `sh -c 'echo $VAR'`) — and note that slim images (nginx-alpine, distroless) often ship no `nc`/`curl`/`wget`, and a `dash` shell has no `/dev/tcp`, so TCP reachability cannot be probed from inside such a pod without adding tooling.
