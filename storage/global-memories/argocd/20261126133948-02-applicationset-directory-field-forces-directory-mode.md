---
date: 2026-11-26
keywords: ["argocd", "applicationset", "directory", "recurse", "kustomize", "missingkey"]
aliases: ["templatePatch", "syncOptions", "non-recursive directory source"]
---

## A `directory` field on a shared ApplicationSet template changes every app's source type

`ApplicationSource.ExplicitType()` returns the type from whichever source field is non-nil, so adding `source.directory: {recurse: true}` to an ApplicationSet template makes Argo treat **every** generated Application as a directory source — including the ones whose path has a `kustomization.yaml`, which lose their patches and generated names. That is why a plain-directory app in a kustomize-based tree must get its own `kustomization.yaml` listing every applied file (nested `deployments/` too), rather than a `recurse` flag on the template: Argo's directory source is non-recursive by default, and anything not listed is not applied — and, with `prune: true`, is deleted.

The same template can carry a `templatePatch` string to pass per-app `syncOptions` through from a `files` generator. That patch `range`s over the key, and with `goTemplateOptions: ["missingkey=error"]` a single `app.yaml` missing it fails the render for the whole ApplicationSet — no chart Applications are generated at all, not just the incomplete one. Give every file the key (`syncOptions: []` is valid) before switching the template to read it.
