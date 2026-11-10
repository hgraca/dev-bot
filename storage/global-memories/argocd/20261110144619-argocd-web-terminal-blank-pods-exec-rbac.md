---
date: 2026-11-10
keywords: ["argocd", "web-terminal", "pods-exec", "rbac", "hijacked-connection"]
trigger-on: ["argocd-web-terminal", "argocd-exec-rbac"]
---

## A blank ArgoCD web terminal is a pods/exec 403, not a websocket problem

The terminal tab opens, the cursor blinks, nothing can be typed, and nothing is logged except `terminal session starting` followed by `http: response.WriteHeader on hijacked connection` / `http: response.Write on hijacked connection from fmt.Fprintln`. That pair is `http.Error(w, "Failed to exec container", 400)` in `server/application/terminal.go` — the handler hijacks the connection for the websocket first, so the error body is written to a socket the browser has already abandoned. The failure is in the server→apiserver `pods/exec` call, which uses the `argocd-server` ServiceAccount; upstream `manifests/install.yaml` grants only `get` on `pods`/`pods/log` and never `create` on `pods/exec`. Reproduce it without ArgoCD by running the same exec as another identity (`kubectl exec -n <ns> <pod> -c <c> -- /bin/sh -c true`): the Forbidden string names the resource you must grant. Two traps: ArgoCD's docs claim Kubernetes ≥1.31 makes `get` on the pod sufficient — verified false on EKS v1.35, the real request still 403s — and `kubectl auth can-i create pods/exec` can answer `yes` while the actual request is forbidden, so never trust can-i as proof. Fix by adding `apiGroups: [""], resources: ["pods/exec"], verbs: ["create"]` to the `argocd-server` ClusterRole; if the install is GitOps-managed, patch it in the pinned kustomization, otherwise the next `--server-side --force-conflicts` apply drops it again.
