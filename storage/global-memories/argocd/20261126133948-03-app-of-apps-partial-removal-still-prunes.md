---
date: 2026-11-26
keywords: ["argocd", "app-of-apps", "prune", "adoption"]
aliases: ["pruned application", "moving manifests out of an app-of-apps"]
---

## Removing one manifest from an app-of-apps directory still prunes it

An Application that manages a directory compares what it finds with what is live. Removing **one** of the files it renders while others remain leaves it perfectly able to render, so the resource that disappeared is pruned — observed as `Application/<name>: Pruned` in `status.operationState.syncResult.resources`. Only a directory that is *gone entirely* stops this, because a missing path fails manifest generation and Argo cannot compare at all.

So migrating a manifest out of an app-of-apps is not "move the file": the Application it declared is deleted on the next sync unless (a) the file moves together with every other file in that directory, (b) the Application is orphaned/deleted first, or (c) the target Application already owns the object. When the pruned object is itself an Application, check whether it carried the resources finalizer — without it the workloads survive, and the object has to be recreated by hand.
