---
date: 2026-10-12
keywords: ["k8s", "kustomize", "json6902", "annotations", "strategic-merge"]
trigger-on: ["kustomize-patch-pod-template", "json6902-add-optional-map"]
---

## JSON-6902 `add` cannot create an optional map — patch pod-template annotations with a strategic-merge patch

RFC-6902 `add` requires the addressed member's **parent** to exist; it never creates intermediate maps. A kustomize JSON-6902 patch targeting `/spec/template/metadata/annotations/<key>` therefore fails the build (`add operation does not apply: doc is missing path`) whenever the pod template has no `annotations` map — which is optional, unlike `labels` (a Deployment's `spec.selector` forces template labels to exist, so the same patch on `/spec/template/metadata/labels/...` succeeds). Verified on kustomize v5.4.3: the labels path works on every workload kind; the annotations path works only when the template already carries annotations. Fix: carry the annotation in a **strategic-merge patch** (one per workload kind, since the patch is typed by kind), which creates the map when absent and merges when present. Do **not** pre-add the map with `- op: add, path: /spec/template/metadata/annotations, value: {}` — `add` replaces an existing member wholesale, wiping every pre-existing annotation.
