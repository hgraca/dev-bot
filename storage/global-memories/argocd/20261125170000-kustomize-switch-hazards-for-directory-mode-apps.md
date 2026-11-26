---
date: 2026-11-25
keywords: ["argocd", "kustomize", "directory-recurse", "image-alias", "docker-hub"]
trigger-on: ["argocd-directory-mode", "kustomize-migration", "unqualified-image-name"]
---

## Migrating an ArgoCD directory-mode app to kustomize: three traps

An Application with `spec.source.directory.recurse: true` applies every YAML in the path as raw manifests. Adding a `kustomization.yaml` to that directory does **not** switch it to kustomize — Argo tries to apply the `Kustomization` object itself and the sync fails with `no matches for kind "Kustomization"`. Setting `spec.source.kustomize: {}` explicitly is what forces kustomize rendering; merely deleting `directory` is not enough, because Argo auto-detects from repo contents and, with no kustomization present yet, falls back to directory mode with `recurse` defaulting to **false** — silently dropping every manifest in subdirectories.

The worst trap is the image alias. Kustomize `images:` entries rewrite short names, so a manifest says `image: nginx` and `image: php-fpm`. If any directory-mode sync runs while those short names are in the repo, Kubernetes resolves them against Docker Hub: `nginx` **exists** (so the workload silently runs public `nginx:latest` instead of the pinned ECR digest), and `php-fpm` does not, so the container `ImagePullBackOff`s. Never let an alias-carrying manifest coexist with directory-mode rendering: patch `kustomize: {}` first, confirm the app errors with "unable to find kustomization.yaml" and applies nothing, then merge the kustomization, then merge the alias swap as a separate change.

Finally, `syncPolicy.automated: {}` without `prune: true` means a transient render loss does not delete workloads, but it also silently stops managing them — check the policy before assuming either outcome.
