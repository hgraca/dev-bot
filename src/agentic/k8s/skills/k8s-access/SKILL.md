---
name: devbot:k8s-access
description: "Use when reading, debugging, or deploying to a GET-E Kubernetes cluster, or when kubectl reports an expired SSO token. Triggers on 'kubectl', 'kubeconfig', 'get pods', 'cluster', 'pods/exec'."
---

# Kubernetes Access

How an agent reaches the GET-E clusters. The kubeconfig is **generated per project** by the `k8s` module's `init.sh`; never hand-edit it and never point `kubectl` at `~/.kube/config`.

## When to Apply

- Reading cluster state: pods, logs, deployments, events, ArgoCD applications
- Debugging why a workload is crash-looping, unready, evicted or not deployed
- Confirming a deploy landed (image tag, rollout status, pod start time)

## Always use `devbot kube`

```sh
devbot kube env      [path]   # KUBECONFIG + current context (never credentials)
devbot kube contexts [path]   # cluster name, context, region
devbot kube run      [path] -- get pods -n core
devbot kube run      [path] -- logs -n core deploy/transfers --tail=100
devbot kube run      [path] -- get applications -n argocd
```

`path` defaults to the current directory. The command resolves the project's generated kubeconfig and execs `kubectl` against the right context — so the hashed filename and the context name never have to be reconstructed. Credentials come from the catalogue's `credential_env`: each entry exports its key (`AWS_ACCESS_KEY_ID`) from the `${VAR}` it references (`AWS_KEY`), read from your environment at call time — so the **referenced** variables must be set, not the keys. `devbot kube env` prints them; the generated `.env` holds only `KUBECONFIG`.

## Why not plain `kubectl`

- The generated file is `~/.kube/devbot/<project>-<hash>.yaml`; the hash is derived from the absolute project path and is not guessable.
- The generated contexts (`gete-prod-ro`, `gete-staging-rw`) use the devbot AWS profile. The contexts in `~/.kube/config` use **SSO**; when that session lapses they fail with `Token has expired and refresh failed`. Use `devbot kube` instead of re-pointing or refreshing those contexts.
- Each project's file contains only the clusters that project opted into. Two projects cannot widen each other's access.

## What the identity can do

`kubectl auth whoami` shows the groups the credentials land in:

| Group                  | Grants                                                                                                           |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `gete-agents-readonly` | cluster-wide `get/list/watch` — including `pods/log` — with **no** secrets, exec, port-forward or token creation |
| `gete-agents-writer`   | staging only: create/update/patch/delete workloads in the **`default`** namespace                                |

Consequences worth remembering:

- `pods/exec` is denied by design. To inspect a datastore, use the `datasources` module or the SigNoz metrics rather than trying to exec into the pod.
- The writer Role is namespaced to `default`. `core`, `kube-system`, `argocd` and `otel-collector` are read-only even on staging.
- No secrets are readable — never attempt `get secret`, and never ask for one to be added to the role.

## Gotchas

- **After changing `.devbot.project.jsonc` or the global `kubectl` catalogue, run `devbot reinit <path>`.** The kubeconfig is rendered, not read live; a stale file lists the previous selection.
- **Production is read-only.** There is no writable production context; manifest changes go through the GitOps repo (`k8s-gete`) and ArgoCD.
- **Do not apply manifests with `kubectl apply` on staging** unless the task says so — staging is also ArgoCD-managed from `k8s-gete-dev`, and an imperative apply is reverted on the next sync.
