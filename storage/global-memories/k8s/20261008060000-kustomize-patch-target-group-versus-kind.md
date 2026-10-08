---
date: 2026-10-08
keywords: ["k8s", "kustomize", "patch", "target", "controllerrevision"]
trigger-on: ["kustomize-edit-add-patch", "kustomize-patch-target"]
supersedes: ["k8s/20261007193600-kustomize-edit-add-patch-pod-template-label.md"]
---

## A kustomize patch target matches by group _and_ kind — the group alone is too broad

`kustomize edit add patch --path P --group apps` writes `target: {group: apps}`, which matches **every** resource in the apps group — including `ControllerRevision`, which has no `/spec/template`. A JSON patch that adds `/spec/template/metadata/labels/...` then fails the build outright (`add operation does not apply: doc is missing path`) rather than being skipped. Target each kind instead — `--group apps --kind Deployment`, `--kind ReplicaSet`, `--kind StatefulSet`, `--kind DaemonSet` are the complete set of apps kinds that expose a pod template. Verified on v5.4.3 with all six kinds in one kustomization: the four workload kinds get the label on their pod template, Services and ControllerRevisions are untouched, `spec.selector.matchLabels` stays unchanged, and `kustomize build` exits 0.

Two more semantics decide idempotent versus silently stale:

- `edit add patch` **appends**. Adding the same path with a different target leaves two entries and the old target keeps applying.
- `edit remove patch` removes only an entry whose flags **match it exactly** — `--path` alone matches nothing when the entry carries a target, and a target-less removal is a no-op against a targeted entry. To migrate a target, drop every form it may have taken (`--kind Deployment`, `--group apps`, and each `--group apps --kind X`) and re-add. Guarding the add with a `grep` instead is the trap: a service already holding the old entry satisfies the guard, so its target never changes.
