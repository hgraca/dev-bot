---
date: 2026-10-27
keywords: ["k8s", "kustomize", "set image", "digest pin", "gitops"]
trigger-on: ["kustomize-edit-set-image", "gitops-digest-pin"]
---

## kustomize edit set image matches the name parsed from the manifests

`kustomize edit set image <name>=<repo>@<digest>` matches on the image name parsed out of each manifest reference, not on an existing `images:` entry's `name`. When one service's two images come from a single ECR repository and the manifests pin the full reference inline, both containers parse to the same name: the deploy workflow's default keys (`php-fpm`, `nginx`) match nothing and the run pins nothing (a silent no-op), while passing the repository as the key rewrites both containers to the last digest (nginx running the php-fpm image). Give the containers distinct logical names (`image: php-fpm`, `image: nginx`) and keep the digests under `images:`. Because a non-matching key is silent, a deploy workflow must render the service after pinning and fail when the full `repo@digest` reference is absent from the output — otherwise the job reports success and ships nothing.
