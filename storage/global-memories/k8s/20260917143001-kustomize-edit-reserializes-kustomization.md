---
date: 2026-09-17
keywords: ["k8s", "kustomize", "formatting", "gitops"]
trigger-on: ["kustomize-edit", "kustomization-formatting"]
---

## `kustomize edit` re-serializes the whole kustomization.yaml, so its committed formatting is transient

`kustomize edit set image` — what a GitOps CI deploy job typically runs to bump image digests — rewrites the entire `kustomization.yaml` through kustomize's own YAML serializer: sequence indentation normalises to the flat style (`- literals:` at column 0) and mapping keys are emitted alphabetically sorted (`literals`, `name`, `options`). A file hand-written in the indented style is therefore flattened by the next CI deploy. In `k8s-gete-dev` this happened inside a `github-actions[bot]` commit that also bumped a digest, and the reformat later caused a rebase conflict against a hand-written patch in the same file. Two consequences: do not treat any single committed indentation style as authoritative, and do not run a formatter (`format-yml` / prettier) over these files to "tidy" them — it rewrites the whole file and buries the real change. Keep the patch minimal and expect `kustomize edit` to normalise it anyway.
