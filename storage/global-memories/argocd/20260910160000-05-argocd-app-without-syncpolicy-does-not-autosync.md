---
date: 2026-09-10
keywords: ["argocd", "syncpolicy", "autosync", "gitops"]
trigger-on: ["argocd-application-sync", "argocd-manual-sync"]
---

## An ArgoCD Application without a syncPolicy never auto-syncs

If an Application has no `.spec.syncPolicy` (in particular no `syncPolicy.automated`), a push to its source repo leaves it `OutOfSync` until someone triggers a sync manually — the manifest change never reaches the cluster. Diagnose by checking `.spec.syncPolicy` and `.status.resources[] | select(.status != "Synced")`; a commit applied to one app but not another usually means the other app is manual-sync. Note an app can also be `Synced` yet not reflect the latest commit if it synced before the push.
