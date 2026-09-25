---
date: 2026-09-25
keywords: ["argocd", "managedFields", "tracking-id", "provenance", "application"]
trigger-on: ["argocd-application-ownership", "who-created-this-resource", "kubectl-managedfields"]
---

## Finding who actually creates a resource: `--show-managed-fields`, and ArgoCD's `tracking-id`

`kubectl get -o json` **hides `metadata.managedFields` by default**, which makes it look as though nothing recorded the writer — pass `--show-managed-fields=true` to see the manager names (`kubectl-client-side-apply`, `kubectl-patch`, `kubectl-rollout`, `argocd-application-controller`, `argocd-server`, `Terraform`, `kube-controller-manager`), which in one read distinguished a Deployment patched by hand from one owned by a controller. For an ArgoCD-managed object the `argocd.argoproj.io/tracking-id` annotation is the sharper signal, because it encodes `<owning-application>:<group>:<kind>:<namespace>/<name>`: an object with a tracking-id is a child of an app-of-apps, while an empty one means it was created directly through the UI or `argocd app create` and therefore has no manifest anywhere. On one cluster that separated **7 Applications declared in git** — owned by two app-of-apps whose sources are repository directories carrying `directory.recurse: true` — from **17 that existed only as live objects**, which is what made "just add a file to the repo" the wrong plan for a new cluster-level component there. The placement corollary: a component can only be expressed in git where an app-of-apps already recurses, so joining a new directory means creating the parent Application first, and when only a recursed path is available, putting a cluster-infrastructure component in an unrelated app's directory is the cheap, precedented option.
