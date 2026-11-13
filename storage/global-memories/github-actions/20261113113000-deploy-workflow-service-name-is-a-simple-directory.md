---
date: 2026-11-13
keywords: ["github-actions", "dev-tools", "service_name", "service_path", "gitops"]
aliases: ["Resolve the GitOps service path", "must be a simple directory name", "deploy workflow naming"]
trigger-on: ["dev-tools-deploy-workflow", "gitops-service-path"]
---

## Deploy workflow `SERVICE_NAME` is a directory name, not a GitOps path

In the get-e/dev-tools reusable deploy workflows (`dev_tools-deploy_php_nginx.yml`, `dev_tools-deploy_node.yml`) from 0.7.42.0 on, `SERVICE_NAME` must match `[A-Za-z0-9._-]+`; the "Resolve the GitOps service path" step rejects anything with a `/` before the path resolver runs (`ERROR: SERVICE_NAME must be a simple directory name`). Discovery then tries `src/manifests/*/<SERVICE_NAME>` and `default/services/<SERVICE_NAME>` only. A caller whose GitOps layout nests a namespace folder under `default/services` — e.g. `default/services/positioning-activities/aai-new` — can express neither with a bare name, so it must pass the app name as `SERVICE_NAME` plus the full folder as `SERVICE_PATH` (explicit `SERVICE_PATH` wins over discovery). Callers that passed a namespaced value like `positioning-activities/<app>` as `SERVICE_NAME` worked before 0.7.42.0 and fail afterwards, so a dev-tools bump that rewrites these workflows is a breaking change for every consumer with a nested layout.
