---
date: 2026-10-07
keywords: ["k8s", "kustomize", "patch", "label", "json-pointer"]
trigger-on: ["kustomize-edit", "kustomize-patch", "pod-template-label"]
superseded_by: ["k8s/20261008060000-kustomize-patch-target-group-versus-kind.md"]
---

## Adding a pod-template label from a script: `kustomize edit add patch`, never `commonLabels`

> **Superseded in part by** `k8s/20261008060000-kustomize-patch-target-group-versus-kind.md` (2026-10-08) — the `--kind Deployment` target shown here leaves ReplicaSet, StatefulSet and DaemonSet workloads unlabelled; target each kind.

To set a label on `spec.template.metadata.labels` from a deploy script, write a JSON-6902 patch file and register it once:

    kustomize edit add patch --path commit-sha.patch.yaml --kind Deployment

with `commit-sha.patch.yaml` holding `- op: add` / `path: /spec/template/metadata/labels/<key>` / `value: "<v>"`. `--kind` scopes the patch, which matters: a patch with **no target applies to every resource** in the kustomization, and a Service or HTTPRoute has no pod template, so the build or the apply fails. Verified on kustomize v5.4.3 — the label lands on the pod template and `spec.selector.matchLabels` is untouched, so the Deployment stays applyable.

Do **not** reach for `commonLabels` (or `labels:` with `includeSelectors`): either mutates the Deployment selector, which is immutable, and the apply is rejected. Two more details: `kustomize edit add patch` **appends** rather than replaces, so guard it with `grep -q <patch-file> kustomization.yaml` before adding and rewrite the patch _file_ each run to update the value; and a label key containing `/` must escape it as `~1` in the JSON pointer, so `gete.io/commit-sha` becomes `/spec/template/metadata/labels/gete.io~1commit-sha`.
