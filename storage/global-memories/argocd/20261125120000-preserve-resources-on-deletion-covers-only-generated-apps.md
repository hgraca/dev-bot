---
date: 2026-11-25
keywords: ["argocd", "preserveResourcesOnDeletion", "ApplicationSet", "finalizer", "application-rename"]
aliases: ["orphan application deletion", "cascade delete application", "preserve resources"]
---

## preserveResourcesOnDeletion protects only ApplicationSet-generated Applications

`spec.syncPolicy.preserveResourcesOnDeletion: true` on an ApplicationSet is inherited by the Applications it **generates** and by nothing else. An Application created by hand (UI, CLI, or `kubectl apply`) keeps its own deletion semantics: it deletes its whole resource tree only if it carries the `resources-finalizer.argocd.argoproj.io` finalizer. Check `.metadata.finalizers` before planning any delete — in the GET-E prod cluster every hand-made Application reported `<none>`, so even a plain cascading `kubectl delete application` orphaned the workloads and the ApplicationSet setting was irrelevant. Do not invert this: a finalizer-bearing Application must be deleted with `--cascade=orphan` if the workloads are meant to survive. The same rename trap applies to generated Applications — the Application name is the path basename, so renaming a directory deletes the old Application and creates a new one, and preservation only holds while the ApplicationSet setting is in place.
