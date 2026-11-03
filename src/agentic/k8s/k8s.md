# Kubernetes access

Cluster access goes through the devbot `k8s` module — never the plain `~/.kube/config`:

- `devbot kube contexts <project>` — the clusters that project may reach
- `devbot kube env <project>` — its `KUBECONFIG` and current context (no credentials)
- `devbot kube run <project> -- <kubectl args>` — kubectl against the generated kubeconfig

The kubeconfig is `~/.kube/devbot/<project_name>-<8-hex>.yaml`, rendered by `devbot init` (not read live — re-run `devbot reinit <project>` after changing the selection). Contexts are `gete-prod-ro` and `gete-staging-rw`. The `~/.kube/config` contexts use SSO and fail with `Token has expired and refresh failed` — that error means wrong context, not no access.

Identity lands in `gete-agents-readonly` (cluster-wide get/list/watch, no secrets/exec/port-forward) and `gete-agents-writer` (staging only, namespaced to `default`). `pods/exec` is denied by design; use the `datasources` module or SigNoz metrics instead of exec-ing into a pod.
