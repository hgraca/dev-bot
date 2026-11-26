---
date: 2026-11-25
keywords: ["argocd", "prune", "syncPolicy"]
aliases: ["argocd keeps deleted resources", "OutOfSync after removing a resource", "app path does not exist"]
trigger-on: ["argocd-prune"]
---

## Without `prune`, removing a resource from git deletes nothing

`syncPolicy.automated: {}` (or `automated` without `prune: true`) applies additions and updates but never deletes a resource that disappears from git: the object keeps running and the Application reports `OutOfSync` forever, with no error to explain why. If the source *path* itself is removed, the app degrades further to `Unknown` with `failed to generate manifest … <path>: app path does not exist`, and at that point it cannot prune even if prune were enabled — the fix is a manual `kubectl delete` per object, then deleting the Application. Before enabling `prune`, diff live against desired (`argocd app diff <app>`): prune deletes anything present in the cluster and absent from git, including resources added by hand during an incident. Durable fix is to own the Application from an ApplicationSet in git rather than a hand-made object.
